import AppKit
import FlickCore
import Testing

@testable import Flick

@MainActor
struct ShortcutMenuTests {
    @Test func actualMenusHaveTheExpectedOrderOptionsAndOffPlacement() throws {
        try withHarness { harness in
            let menu = harness.app.rebuildMenu()
            #expect(
                menu.items.prefix(3).map(\.title) == [
                    "Previous / Next Desktop\t⌥[ / ⌥]",
                    "Go to Desktop\tOff",
                    "Move Window\t⌥⇧[ / ⌥⇧]",
                ]
            )
            let switching = try harness.submenu("Previous / Next Desktop")
            let jumping = try harness.submenu("Go to Desktop")
            let moving = try harness.submenu("Move Window")
            #expect(switching.items.map(\.title) == ["⌃← / ⌃→", "⌥[ / ⌥]", "⌃⌥[ / ⌃⌥]", "", "Off"])
            #expect(jumping.items.map(\.title) == ["⌃1–9", "⌥1–9", "⌃⌥1–9", "", "Off"])
            #expect(moving.items.map(\.title) == ["⌃⇧← / ⌃⇧→", "⌥⇧[ / ⌥⇧]", "⌃⌥⇧[ / ⌃⌥⇧]"])
            for submenu in [switching, jumping] {
                #expect(submenu.items.filter(\.isSeparatorItem).count == 1)
                #expect(submenu.items[3].isSeparatorItem)
                #expect(submenu.items.last?.title == "Off")
            }
            #expect(moving.items.allSatisfy { !$0.isSeparatorItem })
            #expect(switching.items.filter { $0.state == .on }.map(\.title) == ["⌥[ / ⌥]"])
            #expect(jumping.items.filter { $0.state == .on }.map(\.title) == ["Off"])
            #expect(moving.items.filter { $0.state == .on }.map(\.title) == ["⌥⇧[ / ⌥⇧]"])
            #expect(harness.move.attempts.isEmpty)
            #expect(harness.switching.attempts.isEmpty)
            #expect(harness.jump.attempts.isEmpty)
        }
    }

    @Test func everyNumberedMenuChoiceRegistersAndPersistsTheIntendedPreset() throws {
        try withHarness { harness in
            harness.preferences.switchingEnabled = false
            for preset in JumpShortcutPreset.allCases {
                try harness.choose(preset.label, in: "Go to Desktop")
                #expect(harness.reloaded.jumpPreset == preset)
                #expect(harness.jump.registered == preset.bindings.map(\.shortcut))
                if preset != .off {
                    #expect(harness.jump.attempts.last == .jump(preset))
                }
                #expect(!harness.preferences.switchingEnabled)
                #expect(harness.preferences.movePreset == .optionBrackets)
                #expect(harness.move.attempts.isEmpty)
                #expect(harness.switching.attempts.isEmpty)
                try harness.expectSelection(preset.label, in: "Go to Desktop")
            }
            #expect(
                harness.jump.attempts == [
                    .jump(.controlNumbers), .jump(.optionNumbers), .jump(.controlOptionNumbers),
                ]
            )
            #expect(harness.alerts.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func relativeMenuChoicesReachOnlyTheirOwnRegistration(moving: Bool) throws {
        let action: SpaceAction = moving ? .moveWindow : .switchSpace
        try withHarness { harness in
            harness.preferences.switchingEnabled = false
            harness.preferences.jumpPreset = .controlOptionNumbers
            let title = moving ? "Move Window" : "Previous / Next Desktop"
            let keys = moving ? harness.move : harness.switching
            for preset in ShortcutPreset.allCases {
                try harness.choose(preset.label(for: action), in: title)
                #expect(keys.attempts.last == .relative(preset, action))
                #expect(
                    keys.registered
                        == Direction.allCases.map { preset.shortcut(for: $0, action: action) }
                )
                #expect(
                    (moving ? harness.reloaded.movePreset : harness.reloaded.switchPreset) == preset
                )
                #expect(
                    (moving ? harness.preferences.switchPreset : harness.preferences.movePreset)
                        == .optionBrackets
                )
                #expect(harness.preferences.switchingEnabled == !moving)
                #expect(harness.preferences.jumpPreset == .controlOptionNumbers)
                try harness.expectSelection(preset.label(for: action), in: title)
            }
            #expect((moving ? harness.switching : harness.move).attempts.isEmpty)
            #expect(harness.jump.attempts.isEmpty)
            if !moving {
                try harness.choose("Off", in: title)
                #expect(!harness.reloaded.switchingEnabled)
                #expect(harness.reloaded.switchPreset == .controlOptionBrackets)
                #expect(keys.registered.isEmpty)
                #expect(keys.attempts.count == ShortcutPreset.allCases.count)
                try harness.expectSelection("Off", in: title)
            }
            #expect(harness.alerts.isEmpty)
        }
    }

    @Test(arguments: JumpShortcutPreset.allCases.map(\.rawValue))
    func failedNumberedSelectionRestoresPreviousPreferencesBindingsAndMenu(oldValue: String) throws
    {
        let old = try #require(JumpShortcutPreset(rawValue: oldValue))
        try withHarness { harness in
            harness.preferences.jumpPreset = old
            harness.app.menuWillOpen(harness.app.rebuildMenu())
            let previousMove = harness.move.registered
            let previousSwitch = harness.switching.registered
            let replacement: JumpShortcutPreset =
                old == .controlNumbers ? .optionNumbers : .controlNumbers
            harness.jump.rejectNextRegistration = true

            try harness.choose(replacement.label, in: "Go to Desktop")

            #expect(harness.reloaded.jumpPreset == old)
            #expect(harness.jump.registered == old.bindings.map(\.shortcut))
            #expect(
                harness.jump.attempts
                    == (old == .off
                        ? [.jump(replacement)]
                        : [.jump(old), .jump(replacement), .jump(old)])
            )
            #expect(harness.move.registered == previousMove)
            #expect(harness.switching.registered == previousSwitch)
            #expect(harness.alerts == ["Registration rejected by test."])
            try harness.expectSelection(old.label, in: "Go to Desktop")
            #expect(
                !harness.app.rebuildMenu().items.contains {
                    $0.title == "⚠ Jump Shortcuts Unavailable…"
                }
            )
        }
    }

    @Test(arguments: [false, true])
    func failedRelativeSwitchRestoresBothPresetAndEnabledState(wasEnabled: Bool) throws {
        try withHarness { harness in
            harness.preferences.switchPreset = .controlOptionBrackets
            harness.preferences.switchingEnabled = wasEnabled
            harness.app.menuWillOpen(harness.app.rebuildMenu())
            harness.switching.rejectNextRegistration = true

            try harness.choose("⌃← / ⌃→", in: "Previous / Next Desktop")

            #expect(harness.reloaded.switchPreset == .controlOptionBrackets)
            #expect(harness.reloaded.switchingEnabled == wasEnabled)
            let previous = Direction.allCases.map {
                ShortcutPreset.controlOptionBrackets.shortcut(for: $0, action: .switchSpace)
            }
            #expect(harness.switching.registered == (wasEnabled ? previous : []))
            #expect(
                harness.switching.attempts
                    == (wasEnabled
                        ? [
                            .relative(.controlOptionBrackets, .switchSpace),
                            .relative(.controlArrows, .switchSpace),
                            .relative(.controlOptionBrackets, .switchSpace),
                        ]
                        : [.relative(.controlArrows, .switchSpace)])
            )
            #expect(harness.alerts == ["Registration rejected by test."])
            try harness.expectSelection(
                wasEnabled ? "⌃⌥[ / ⌃⌥]" : "Off",
                in: "Previous / Next Desktop"
            )
        }
    }

    @Test func failedMoveSelectionRestoresPreviousPreferencesAndBindings() throws {
        try withHarness { harness in
            harness.preferences.movePreset = .controlOptionBrackets
            harness.app.menuWillOpen(harness.app.rebuildMenu())
            harness.move.rejectNextRegistration = true

            try harness.choose("⌃⇧← / ⌃⇧→", in: "Move Window")

            #expect(harness.reloaded.movePreset == .controlOptionBrackets)
            #expect(
                harness.move.registered
                    == Direction.allCases.map {
                        ShortcutPreset.controlOptionBrackets.shortcut(for: $0, action: .moveWindow)
                    }
            )
            #expect(
                harness.move.attempts == [
                    .relative(.controlOptionBrackets, .moveWindow),
                    .relative(.controlArrows, .moveWindow),
                    .relative(.controlOptionBrackets, .moveWindow),
                ]
            )
            #expect(harness.alerts == ["Registration rejected by test."])
            try harness.expectSelection("⌃⌥⇧[ / ⌃⌥⇧]", in: "Move Window")
        }
    }

    private func withHarness(_ body: (MenuHarness) throws -> Void) rethrows {
        let suite = "Flick.ShortcutMenuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(MenuHarness(defaults: defaults))
    }
}

@MainActor
private final class MenuHarness {
    let preferences: ShortcutPreferences
    let move = RecordingHotKeys()
    let switching = RecordingHotKeys()
    let jump = RecordingHotKeys()
    private(set) var alerts: [String] = []
    lazy var app = AppDelegate(
        shortcuts: preferences,
        moveHotkeys: move,
        switchHotkeys: switching,
        jumpHotkeys: jump,
        presentAlert: { [weak self] _, message in self?.alerts.append(message) }
    )
    var reloaded: ShortcutPreferences { ShortcutPreferences(defaults: preferences.defaults) }

    init(defaults: UserDefaults) {
        preferences = ShortcutPreferences(defaults: defaults)
    }

    func submenu(_ title: String) throws -> NSMenu {
        let parent = try #require(
            app.rebuildMenu().items.first { $0.title.hasPrefix("\(title)\t") }
        )
        return try #require(parent.submenu)
    }

    func choose(_ label: String, in title: String) throws {
        let item = try #require(try submenu(title).items.first { $0.title == label })
        #expect(item.isEnabled)
        let action = try #require(item.action)
        let target = try #require(item.target as? NSObject)
        #expect(target === app)
        #expect(target.responds(to: action))
        // Dispatch the actual item's target/action without showing a menu or launching the app.
        if NSStringFromSelector(action).hasSuffix(":") {
            _ = target.perform(action, with: item)
        } else {
            _ = target.perform(action)
        }
    }

    func expectSelection(
        _ label: String,
        in title: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let parent = try #require(
            app.rebuildMenu().items.first { $0.title.hasPrefix("\(title)\t") }
        )
        #expect(parent.title == "\(title)\t\(label)", sourceLocation: sourceLocation)
        let submenu = try #require(parent.submenu)
        #expect(
            submenu.items.filter { $0.state == .on }.map(\.title) == [label],
            sourceLocation: sourceLocation
        )
    }
}

@MainActor
private final class RecordingHotKeys: HotKeyRegistering {
    enum Attempt: Equatable {
        case relative(ShortcutPreset, SpaceAction)
        case jump(JumpShortcutPreset)
    }
    var onPress: ((Int) -> Void)?
    var rejectNextRegistration = false
    private(set) var registered: [SpaceShortcut] = []
    private(set) var attempts: [Attempt] = []

    func register(_ preset: ShortcutPreset, action: SpaceAction) throws {
        attempts.append(.relative(preset, action))
        try register(Direction.allCases.map { preset.shortcut(for: $0, action: action) })
    }

    func register(_ preset: JumpShortcutPreset) throws {
        attempts.append(.jump(preset))
        try register(preset.bindings.map(\.shortcut))
    }

    private func register(_ shortcuts: [SpaceShortcut]) throws {
        // Real registration discards old bindings before attempting a new preset.
        unregister()
        if rejectNextRegistration {
            rejectNextRegistration = false
            throw FlickError.message("Registration rejected by test.")
        }
        registered = shortcuts
    }

    func unregister() { registered = [] }
    func stop() { unregister() }
}
