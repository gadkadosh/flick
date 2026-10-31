import AppKit
import ApplicationServices
import FlickCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var spaceIndicator: CurrentSpaceIndicator?
    private let menu = NSMenu()
    private let moveHotkeys: any HotKeyRegistering
    private let switchHotkeys: any HotKeyRegistering
    private let jumpHotkeys: any HotKeyRegistering
    private let mover = WindowMover()
    private let switcher = SpaceSwitcher()
    private var operationTask: Task<Void, Never>?
    private var lastResult = "Ready."
    private var moveRegistrationError: String?
    private var switchRegistrationError: String?
    private var jumpRegistrationError: String?
    private let shortcuts: ShortcutPreferences
    private let presentAlert: ((String, String) -> Void)?

    init(
        shortcuts: ShortcutPreferences = ShortcutPreferences(),
        moveHotkeys: (any HotKeyRegistering)? = nil,
        switchHotkeys: (any HotKeyRegistering)? = nil,
        jumpHotkeys: (any HotKeyRegistering)? = nil,
        presentAlert: ((String, String) -> Void)? = nil
    ) {
        self.shortcuts = shortcuts
        self.moveHotkeys = moveHotkeys ?? HotKeys()
        self.switchHotkeys = switchHotkeys ?? HotKeys(signature: 0x464C_5357)
        self.jumpHotkeys = jumpHotkeys ?? HotKeys(signature: 0x464C_4A50)
        self.presentAlert = presentAlert
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            spaceIndicator = CurrentSpaceIndicator(button: button)
            spaceIndicator?.start()
        }
        statusItem.menu = menu
        menu.autoenablesItems = false
        menu.delegate = self
        let smokeTest = CommandLine.arguments.contains("--smoke-test")
        if !smokeTest {
            moveHotkeys.onPress = { [weak self] index in
                self?.perform(Direction.allCases[index], switching: false)
            }
            switchHotkeys.onPress = { [weak self] index in
                self?.perform(Direction.allCases[index], switching: true)
            }
            jumpHotkeys.onPress = { [weak self] index in
                self?.jumpToDesktop(index + 1)
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
        registerJumpShortcuts()
    }

    private func registerJumpShortcuts() {
        jumpHotkeys.unregister()
        jumpRegistrationError = nil
        guard shortcuts.jumpPreset != .off else { return }
        do {
            try jumpHotkeys.register(shortcuts.jumpPreset)
        } catch {
            jumpRegistrationError = error.localizedDescription
        }
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
        startOperation {
            if switching {
                return try await self.switcher.switchSpace(direction)
            }
            return try await self.mover.move(direction, preset: self.shortcuts.movePreset)
        }
    }

    private func jumpToDesktop(_ number: Int) {
        guard operationTask == nil else {
            NSSound.beep()
            statusItem.button?.toolTip =
                "Wait for the current Space operation before jumping to a desktop."
            return
        }
        startOperation { try await self.switcher.jumpToDesktop(number) }
    }

    private func startOperation(_ operation: @escaping () async throws -> String) {
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                lastResult = try await operation()
            } catch is CancellationError {
                lastResult = "Space operation cancelled."
            } catch {
                lastResult = error.localizedDescription
                NSSound.beep()
            }
            spaceIndicator?.refresh()
            statusItem.button?.toolTip = lastResult
            operationTask = nil
            rebuildMenu()
        }
    }

    @discardableResult
    func rebuildMenu() -> NSMenu {
        menu.removeAllItems()
        addShortcutMenu(
            "Previous / Next Desktop",
            options: ShortcutPreset.allCases.map { $0.label(for: .switchSpace) },
            selected: shortcuts.switchingEnabled
                ? ShortcutPreset.allCases.firstIndex(of: shortcuts.switchPreset) : nil,
            action: #selector(changeSwitchPreset(_:)),
            offAction: #selector(disableSwitching)
        )
        addShortcutMenu(
            "Go to Desktop",
            options: JumpShortcutPreset.allCases.filter { $0 != .off }.map(\.label),
            selected: shortcuts.jumpPreset == .off
                ? nil : JumpShortcutPreset.allCases.firstIndex(of: shortcuts.jumpPreset),
            action: #selector(changeJumpPreset(_:)),
            offAction: #selector(changeJumpPreset(_:))
        )
        addShortcutMenu(
            "Move Window",
            options: ShortcutPreset.allCases.map { $0.label(for: .moveWindow) },
            selected: ShortcutPreset.allCases.firstIndex(of: shortcuts.movePreset),
            action: #selector(changeMovePreset(_:))
        )
        menu.addItem(.separator())
        let login = add("Launch at Login", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { login.title += " (approval needed)" }

        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            add("Grant Accessibility…", action: #selector(grantAccessibility))
        }
        if switchRegistrationError != nil {
            add("⚠ Switch Shortcuts Unavailable…", action: #selector(showShortcutErrors))
        }
        if moveRegistrationError != nil {
            add("⚠ Move Shortcuts Unavailable…", action: #selector(showShortcutErrors))
        }
        if jumpRegistrationError != nil {
            add("⚠ Jump Shortcuts Unavailable…", action: #selector(showShortcutErrors))
        }
        let help = NSMenu()
        help.autoenablesItems = false
        add("Last Result…", action: #selector(showLastResult), to: help)
        if !shortcutOverlaps().isEmpty {
            add("Possible Shortcut Conflicts…", action: #selector(showConflicts), to: help)
        }
        add("Keyboard Shortcuts…", action: #selector(openKeyboardSettings), to: help).toolTip =
            "Select Mission Control in the sidebar."
        help.addItem(.separator())
        add("About Flick…", action: #selector(showAbout), to: help)
        let helpItem = add("Help", action: nil)
        helpItem.submenu = help
        helpItem.isEnabled = true
        add("Quit Flick", action: #selector(quit), key: "q")
        statusItem?.button?.toolTip = lastResult
        return menu
    }

    @discardableResult
    private func add(
        _ title: String,
        action: Selector?,
        key: String = "",
        to parent: NSMenu? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = action != nil
        (parent ?? menu).addItem(item)
        return item
    }

    private func addShortcutMenu(
        _ title: String,
        options: [String],
        selected: Int?,
        action: Selector,
        offAction: Selector? = nil
    ) {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (index, option) in options.enumerated() {
            let item = add(option, action: action, to: submenu)
            item.tag = index
            item.state = selected == index ? .on : .off
            item.isEnabled = operationTask == nil
        }
        if let offAction {
            submenu.addItem(.separator())
            let off = add("Off", action: offAction, to: submenu)
            off.tag = options.count
            off.state = selected == nil ? .on : .off
            off.isEnabled = operationTask == nil
        }
        let label = selected.map { options[$0] } ?? "Off"
        addShortcutSummary(title, label: label, submenu: submenu)
    }

    private func addShortcutSummary(_ title: String, label: String, submenu: NSMenu) {
        let item = add("\(title)\t\(label)", action: nil)
        // Align the summaries without assigning a second set of keyboard shortcuts.
        let font = NSFont.menuFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let titleWidth =
            ("Previous / Next Desktop" as NSString).size(withAttributes: attributes).width
        let labels = [
            shortcuts.switchingEnabled ? shortcuts.switchPreset.label(for: .switchSpace) : "Off",
            shortcuts.movePreset.label(for: .moveWindow), shortcuts.jumpPreset.label,
        ]
        let labelWidth =
            labels.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: ceil(titleWidth + 24 + labelWidth))
        ]
        item.attributedTitle = NSAttributedString(
            string: item.title,
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
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
        let wasEnabled = shortcuts.switchingEnabled
        shortcuts.switchPreset = ShortcutPreset.allCases[item.tag]
        shortcuts.switchingEnabled = true
        registerSwitchShortcuts()
        if let error = switchRegistrationError {
            shortcuts.switchPreset = old
            shortcuts.switchingEnabled = wasEnabled
            registerSwitchShortcuts()
            lastResult = error
            showLastResult()
        }
        rebuildMenu()
    }

    @objc private func changeJumpPreset(_ item: NSMenuItem) {
        let old = shortcuts.jumpPreset
        shortcuts.jumpPreset = JumpShortcutPreset.allCases[item.tag]
        registerJumpShortcuts()
        if let error = jumpRegistrationError {
            shortcuts.jumpPreset = old
            registerJumpShortcuts()
            lastResult = error
            showLastResult()
        }
        rebuildMenu()
    }

    @objc private func disableSwitching() {
        shortcuts.switchingEnabled = false
        registerSwitchShortcuts()
        rebuildMenu()
    }

    @objc private func showShortcutErrors() {
        alert(
            "Shortcut registration",
            [moveRegistrationError, switchRegistrationError, jumpRegistrationError].compactMap {
                $0
            }
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
        let jumpIDs = systemConflicts(
            for: shortcuts.jumpPreset.bindings.map(\.shortcut),
            in: settings
        )
        if !jumpIDs.isEmpty {
            overlaps.append(
                "Jump: \(shortcuts.jumpPreset.label) (system IDs: \(jumpIDs.joined(separator: ", ")))"
            )
        }
        return overlaps
    }

    @objc private func showConflicts() {
        alert(
            "Possible system shortcut overlap",
            "\(shortcutOverlaps().joined(separator: "\n"))\n\nmacOS lists these keys in its preferences, including hidden Shift variants of Mission Control shortcuts that are not shown separately in System Settings. This does not prove macOS will intercept them. If Flick works reliably, no action is needed.\n\nIf keys do not fire, switch twice, or show an animation, choose another Flick preset or disable/reassign the matching shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Mission Control. Reopen Flick's menu to retry registration. Flick does not change your system settings."
        )
    }
    @objc private func showAbout() {
        alert(
            "Flick",
            "Switch Spaces, or move a window and follow it, without animation.\n\nExperimental: uses undocumented macOS APIs. macOS updates may break compatibility. Window moves require Accessibility.\n\nBracket and number shortcuts use physical US-layout key positions. Desktop numbers match Mission Control across displays."
        )
    }
    private func alert(_ title: String, _ message: String) {
        if let presentAlert {
            presentAlert(title, message)
            return
        }
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
        spaceIndicator?.stop()
        moveHotkeys.stop()
        switchHotkeys.stop()
        jumpHotkeys.stop()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if operationTask == nil { registerShortcuts() }
        rebuildMenu()
    }
}
