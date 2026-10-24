import AppKit
import ApplicationServices
import FlickCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let idleImage = NSImage(
        systemSymbolName: "arrow.left.arrow.right",
        accessibilityDescription: "Flick"
    )
    private let busyImage = NSImage(
        systemSymbolName: "hourglass",
        accessibilityDescription: "Space operation in progress"
    )
    private let menu = NSMenu()
    private let hotkeys = HotKeys()
    private let switchHotkeys = HotKeys(signature: 0x464C_5357)
    private let mover = WindowMover()
    private let switcher = SpaceSwitcher()
    private var operationTask: Task<Void, Never>?
    private var lastResult = "Ready."
    private var registrationError: String?
    private var switchRegistrationError: String?
    private let defaults = UserDefaults.standard

    private var preset: MoveShortcutPreset {
        get {
            MoveShortcutPreset(rawValue: defaults.string(forKey: "moveShortcutPreset") ?? "")
                ?? .optionShift
        }
        set { defaults.set(newValue.rawValue, forKey: "moveShortcutPreset") }
    }

    private var switchingEnabled: Bool {
        get { defaults.object(forKey: "spaceSwitchingEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "spaceSwitchingEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = idleImage
        statusItem.menu = menu
        menu.autoenablesItems = false
        menu.delegate = self
        let smokeTest = CommandLine.arguments.contains("--smoke-test")
        if !smokeTest {
            hotkeys.onPress = { [weak self] direction in self?.perform(direction, switching: false)
            }
            switchHotkeys.onPress = { [weak self] direction in
                self?.perform(direction, switching: true)
            }
        }
        registerShortcuts()
        rebuildMenu()
        if smokeTest {
            print("Flick startup smoke test: menu created; Space actions disabled.")
            print(menu.items.filter { !$0.isSeparatorItem }.map(\.title).joined(separator: "\n"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    private func registerShortcuts() {
        registerSwitchShortcuts()
        do {
            let conflicts = systemConflicts(for: preset, in: symbolicHotkeys())
            guard !conflicts.contains("79"), !conflicts.contains("81") else {
                hotkeys.unregister()
                throw FlickError.message(
                    "Move shortcuts must differ from your Mission Control space-switching shortcuts. Choose another preset."
                )
            }
            try hotkeys.register(preset)
            registrationError = nil
        } catch {
            registrationError = error.localizedDescription
            lastResult = error.localizedDescription
        }
    }

    private func registerSwitchShortcuts() {
        switchHotkeys.unregister()
        switchRegistrationError = nil
        guard switchingEnabled else { return }
        do {
            let shortcuts = Direction.allCases.map { SpaceShortcut.switchShortcut(for: $0) }
            guard systemConflicts(for: shortcuts, in: symbolicHotkeys()).isEmpty else {
                throw FlickError.message(
                    "To switch with ⌃← / ⌃→, disable or reassign matching shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Mission Control. Reopen Flick's menu to retry. Window-move shortcuts are unaffected."
                )
            }
            try switchHotkeys.registerSpaceSwitches()
        } catch {
            switchRegistrationError = error.localizedDescription
        }
    }

    private func perform(_ direction: Direction, switching: Bool) {
        if operationTask != nil {
            let queued = switching ? switcher.enqueue(direction) : mover.enqueue(direction)
            if queued {
                statusItem.button?.toolTip =
                    switching
                    ? "Switch queued for the same display (\(switcher.pendingSwitches) waiting)."
                    : "Move queued for the same window (\(mover.pendingMoves) waiting)."
            } else {
                NSSound.beep()
                statusItem.button?.toolTip =
                    "Cannot queue this action: another kind of operation is running, or the queue is full or closed."
            }
            return
        }
        statusItem.button?.image = busyImage
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                if switching {
                    lastResult = try await switcher.switchSpace(direction)
                } else {
                    lastResult = try await mover.move(direction, preset: preset)
                }
            } catch is CancellationError {
                lastResult = "Space operation cancelled."
            } catch {
                lastResult = error.localizedDescription
                NSSound.beep()
            }
            statusItem.button?.image = idleImage
            statusItem.button?.toolTip = lastResult
            operationTask = nil
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        add("Flick · experimental", action: nil)
        add("Move window left: \(preset.label(for: .previous))", action: nil)
        add("Move window right: \(preset.label(for: .next))", action: nil)
        let switching = add("Switch Spaces: ⌃← / ⌃→", action: #selector(toggleSwitching))
        switching.state = switchingEnabled ? .on : .off
        switching.isEnabled = operationTask == nil
        if switchRegistrationError != nil {
            add("⚠ Space-switch shortcuts unavailable…", action: #selector(showShortcutErrors))
        }
        menu.addItem(.separator())
        let shortcutMenu = NSMenu()
        shortcutMenu.autoenablesItems = false
        for (index, option) in MoveShortcutPreset.allCases.enumerated() {
            let item = NSMenuItem(
                title: "\(option.modifiersLabel)[ / \(option.modifiersLabel)]",
                action: #selector(changePreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = preset == option ? .on : .off
            item.isEnabled = operationTask == nil
            shortcutMenu.addItem(item)
        }
        let shortcutItem = add("Move shortcuts", action: nil)
        shortcutItem.submenu = shortcutMenu
        shortcutItem.isEnabled = operationTask == nil

        let login = add("Launch at login", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { login.title += " (approval needed)" }

        menu.addItem(.separator())
        add(
            AXIsProcessTrusted() ? "Accessibility: allowed" : "Accessibility: permission needed",
            action: nil
        )
        add("Grant Accessibility…", action: #selector(grantAccessibility))
        add("Mission Control shortcut settings…", action: #selector(openKeyboardSettings))
        let conflicts = systemConflicts(for: preset, in: symbolicHotkeys())
        if !conflicts.isEmpty {
            add("⚠ System also reserves these shortcuts", action: #selector(showConflicts))
        }
        if registrationError != nil {
            add("⚠ Move shortcuts could not be registered…", action: #selector(showShortcutErrors))
        }
        menu.addItem(.separator())
        let progress =
            switcher.busy
            ? "Switch in progress (\(switcher.pendingSwitches) queued)…"
            : "Move in progress (\(mover.pendingMoves) queued)…"
        add(operationTask != nil ? progress : "Last result…", action: #selector(showLastResult))
        add("About Flick…", action: #selector(showAbout))
        menu.addItem(.separator())
        add("Quit Flick", action: #selector(quit), key: "q")
        statusItem.button?.toolTip = lastResult
    }

    @discardableResult
    private func add(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = action != nil
        menu.addItem(item)
        return item
    }

    @objc private func changePreset(_ item: NSMenuItem) {
        let old = preset
        preset = MoveShortcutPreset.allCases[item.tag]
        registerShortcuts()
        if let error = registrationError {
            preset = old
            registerShortcuts()
            lastResult = error
            showLastResult()
        }
        rebuildMenu()
    }

    @objc private func toggleSwitching() {
        switchingEnabled.toggle()
        registerSwitchShortcuts()
        rebuildMenu()
    }

    @objc private func showShortcutErrors() {
        alert(
            "Shortcut registration",
            [registrationError, switchRegistrationError].compactMap { $0 }.joined(separator: "\n\n")
        )
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            lastResult = "Launch at login: \(error.localizedDescription)"
            showLastResult()
        }
        rebuildMenu()
    }

    @objc private func grantAccessibility() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }
    @objc private func openKeyboardSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")
    }
    private func openSettings(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
    @objc private func showLastResult() { alert("Flick", lastResult) }
    @objc private func showConflicts() {
        let ids = systemConflicts(for: preset, in: symbolicHotkeys()).joined(separator: ", ")
        alert(
            "System shortcut overlap",
            "macOS reserves this key combination too (symbolic hotkey IDs: \(ids)). macOS creates implicit Shift variants of Space-switching shortcuts. If Flick's shortcuts do not fire, choose a different preset in ‘Move shortcuts’. Flick does not edit your system shortcuts."
        )
    }
    @objc private func showAbout() {
        alert(
            "Flick",
            "Switches adjacent desktop Spaces without a slide animation, or moves ordinary windows and follows them. The cursor, window size, and position are left alone.\n\nWindow moves require Accessibility. Both features require compatible undocumented macOS Space APIs. SIP stays enabled. macOS updates may break compatibility; Flick reports unconfirmed moves instead of falling back to dragging. Fullscreen, Stage Manager, and multi-monitor behavior are not yet validated.\n\nBracket shortcuts use physical US-layout bracket keys."
        )
    }
    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let operationTask else { return .terminateNow }
        operationTask.cancel()
        Task {
            await operationTask.value  // Finish confirming the dispatched operation before exiting.
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
        switchHotkeys.stop()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if operationTask == nil { registerShortcuts() }
        rebuildMenu()
    }
}
