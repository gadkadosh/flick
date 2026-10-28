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
        accessibilityDescription: "Moving window"
    )
    private let menu = NSMenu()
    private let hotkeys = HotKeys()
    private let mover = WindowMover()
    private var moveTask: Task<Void, Never>?
    private var lastResult = "Ready."
    private var registrationError: String?
    private let defaults = UserDefaults.standard

    private var preset: MoveShortcutPreset {
        get {
            MoveShortcutPreset(rawValue: defaults.string(forKey: "moveShortcutPreset") ?? "")
                ?? .optionShift
        }
        set { defaults.set(newValue.rawValue, forKey: "moveShortcutPreset") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = idleImage
        statusItem.menu = menu
        menu.autoenablesItems = false
        menu.delegate = self
        let smokeTest = CommandLine.arguments.contains("--smoke-test")
        if !smokeTest {
            hotkeys.onMove = { [weak self] direction in self?.move(direction) }
        }
        registerShortcuts()
        rebuildMenu()
        if smokeTest {
            print("Flick startup smoke test: menu created; move actions disabled.")
            print(menu.items.filter { !$0.isSeparatorItem }.map(\.title).joined(separator: "\n"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    private func registerShortcuts() {
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

    private func move(_ direction: Direction) {
        if moveTask != nil || mover.busy {
            if mover.enqueue(direction) {
                statusItem.button?.toolTip =
                    "Move queued for the same window (\(mover.pendingMoves) waiting)."
            } else {
                NSSound.beep()
                statusItem.button?.toolTip =
                    "Cannot queue another move: the queue is full or the move sequence has finished."
            }
            return
        }
        statusItem.button?.image = busyImage
        moveTask = Task { [weak self] in
            guard let self else { return }
            do {
                lastResult = try await mover.move(direction, preset: preset)
            } catch is CancellationError {
                lastResult = "Move cancelled."
            } catch {
                lastResult = error.localizedDescription
                NSSound.beep()
            }
            statusItem.button?.image = idleImage
            statusItem.button?.toolTip = lastResult
            moveTask = nil
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        add("Flick · experimental", action: nil)
        add("Previous Space: \(preset.label(for: .previous))", action: nil)
        add("Next Space: \(preset.label(for: .next))", action: nil)
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
            item.isEnabled = !mover.busy
            shortcutMenu.addItem(item)
        }
        let shortcutItem = add("Move shortcuts", action: nil)
        shortcutItem.submenu = shortcutMenu
        shortcutItem.isEnabled = !mover.busy

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
            add("⚠ Shortcuts could not be registered", action: #selector(showLastResult))
        }
        menu.addItem(.separator())
        add(
            mover.busy ? "Move in progress (\(mover.pendingMoves) queued)…" : "Last result…",
            action: #selector(showLastResult)
        )
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
            "Moves ordinary windows directly to an adjacent desktop Space and follows without a slide animation. The cursor, window size, and position are left alone.\n\nRequires Accessibility and compatible undocumented macOS Space APIs. SIP stays enabled. macOS updates may break compatibility; Flick reports unconfirmed moves instead of falling back to dragging. Fullscreen, Stage Manager, and multi-monitor behavior are not yet validated.\n\nBracket shortcuts use physical US-layout bracket keys."
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
        guard let moveTask else { return .terminateNow }
        moveTask.cancel()
        Task {
            await moveTask.value  // Finish the current move-and-follow before exiting.
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.stop()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }
}
