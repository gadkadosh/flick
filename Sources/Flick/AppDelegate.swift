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
    private let moveHotkeys = HotKeys()
    private let switchHotkeys = HotKeys(signature: 0x464C_5357)
    private let mover = WindowMover()
    private let switcher = SpaceSwitcher()
    private var operationTask: Task<Void, Never>?
    private var lastResult = "Ready."
    private var moveRegistrationError: String?
    private var switchRegistrationError: String?
    private let shortcuts = ShortcutPreferences()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = idleImage
        statusItem.menu = menu
        menu.autoenablesItems = false
        menu.delegate = self
        let smokeTest = CommandLine.arguments.contains("--smoke-test")
        if !smokeTest {
            moveHotkeys.onPress = { [weak self] direction in
                self?.perform(direction, switching: false)
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
        registerMoveShortcuts()
        registerSwitchShortcuts()
    }

    private func registerMoveShortcuts() {
        do {
            try moveHotkeys.register(shortcuts.movePreset, action: .moveWindow)
            moveRegistrationError = nil
        } catch {
            moveRegistrationError = error.localizedDescription
            lastResult = error.localizedDescription
        }
    }

    private func registerSwitchShortcuts() {
        switchHotkeys.unregister()
        switchRegistrationError = nil
        guard shortcuts.switchingEnabled else { return }
        do {
            try switchHotkeys.register(shortcuts.switchPreset, action: .switchSpace)
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
                    lastResult = try await mover.move(direction, preset: shortcuts.movePreset)
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
        let switchState = shortcuts.switchingEnabled ? "" : " (off)"
        add(
            "Switch Spaces: \(shortcuts.switchPreset.label(for: .switchSpace))\(switchState)",
            action: nil
        )
        add("Move window: \(shortcuts.movePreset.label(for: .moveWindow))", action: nil)
        menu.addItem(.separator())
        let switching = add("Enable Space switching", action: #selector(toggleSwitching))
        switching.state = shortcuts.switchingEnabled ? .on : .off
        switching.isEnabled = operationTask == nil
        addShortcutMenu("Switch shortcuts", action: .switchSpace)
        addShortcutMenu("Move shortcuts", action: .moveWindow)

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
        if !shortcutOverlaps().isEmpty {
            add("⚠ Possible system shortcut overlap…", action: #selector(showConflicts))
        }
        if switchRegistrationError != nil {
            add("⚠ Space-switch shortcuts unavailable…", action: #selector(showShortcutErrors))
        }
        if moveRegistrationError != nil {
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

    private func addShortcutMenu(_ title: String, action: SpaceAction) {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let selected = action == .moveWindow ? shortcuts.movePreset : shortcuts.switchPreset
        for (index, option) in ShortcutPreset.allCases.enumerated() {
            let item = NSMenuItem(
                title: option.label(for: action),
                action: action == .moveWindow
                    ? #selector(changeMovePreset(_:)) : #selector(changeSwitchPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = selected == option ? .on : .off
            item.isEnabled = operationTask == nil
            submenu.addItem(item)
        }
        let item = add(title, action: nil)
        item.submenu = submenu
        item.isEnabled = operationTask == nil
    }

    @objc private func changeMovePreset(_ item: NSMenuItem) {
        let old = shortcuts.movePreset
        shortcuts.movePreset = ShortcutPreset.allCases[item.tag]
        registerMoveShortcuts()
        if let error = moveRegistrationError {
            shortcuts.movePreset = old
            registerMoveShortcuts()
            lastResult = error
            showLastResult()
        }
        rebuildMenu()
    }

    @objc private func changeSwitchPreset(_ item: NSMenuItem) {
        let old = shortcuts.switchPreset
        shortcuts.switchPreset = ShortcutPreset.allCases[item.tag]
        registerSwitchShortcuts()
        if let error = switchRegistrationError {
            shortcuts.switchPreset = old
            registerSwitchShortcuts()
            lastResult = error
            showLastResult()
        }
        rebuildMenu()
    }

    @objc private func toggleSwitching() {
        shortcuts.switchingEnabled.toggle()
        registerSwitchShortcuts()
        rebuildMenu()
    }

    @objc private func showShortcutErrors() {
        alert(
            "Shortcut registration",
            [moveRegistrationError, switchRegistrationError].compactMap { $0 }
                .joined(separator: "\n\n")
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
    private func shortcutOverlaps() -> [String] {
        let settings = symbolicHotkeys()
        var overlaps: [String] = []
        for action in SpaceAction.allCases {
            if action == .switchSpace && !shortcuts.switchingEnabled { continue }
            let preset = action == .moveWindow ? shortcuts.movePreset : shortcuts.switchPreset
            let ids = systemConflicts(for: preset, action: action, in: settings)
            if !ids.isEmpty {
                let name = action == .moveWindow ? "Move" : "Switch"
                overlaps.append(
                    "\(name): \(preset.label(for: action)) (system IDs: \(ids.joined(separator: ", ")))"
                )
            }
        }
        return overlaps
    }

    @objc private func showConflicts() {
        alert(
            "Possible system shortcut overlap",
            "\(shortcutOverlaps().joined(separator: "\n"))\n\nmacOS lists these keys in its preferences, including hidden Shift variants of Mission Control shortcuts that are not shown separately in System Settings. This does not prove macOS will intercept them. If Flick works reliably, no action is needed.\n\nIf keys do not fire, switch twice, or show an animation, choose another Flick preset or disable/reassign the matching Mission Control shortcuts in System Settings. Reopen Flick's menu to retry registration. Flick does not change your system settings."
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
        moveHotkeys.stop()
        switchHotkeys.stop()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if operationTask == nil { registerShortcuts() }
        rebuildMenu()
    }
}
