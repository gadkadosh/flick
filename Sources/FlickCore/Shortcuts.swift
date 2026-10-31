import Carbon
import CoreGraphics
import Foundation

public enum Direction: CaseIterable, Hashable {
    case previous, next
    public var symbolicID: String { self == .previous ? "79" : "81" }
    public var label: String { self == .previous ? "previous" : "next" }
}

/// Quartz key codes and flags, as stored by macOS in AppleSymbolicHotKeys.
public struct SpaceShortcut: Equatable {
    public let keyCode: UInt16
    public let flags: UInt64

    public init(keyCode: UInt16, flags: UInt64) {
        self.keyCode = keyCode
        self.flags = flags
    }

    /// Carbon registration uses different modifier bits from Quartz events.
    /// Convert the modeled shortcut rather than redefining each preset.
    public var carbonModifiers: UInt32 {
        let quartz = CGEventFlags(rawValue: flags)
        var carbon: UInt32 = 0
        for (flag, modifier): (CGEventFlags, Int) in [
            (.maskAlphaShift, alphaLock), (.maskShift, shiftKey),
            (.maskControl, controlKey), (.maskAlternate, optionKey),
            (.maskCommand, cmdKey),
        ] where quartz.contains(flag) {
            carbon |= UInt32(modifier)
        }
        return carbon
    }

    public static func read(direction: Direction, from hotkeys: [String: Any]) -> SpaceShortcut? {
        guard let entry = hotkeys[direction.symbolicID] as? [String: Any],
            (entry["enabled"] as? NSNumber)?.boolValue == true,
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [NSNumber],
            parameters.count == 3
        else { return nil }
        let code = parameters[1].intValue
        guard (0..<128).contains(code) else { return nil }
        // Reject unknown modifier bits rather than synthesize a different shortcut.
        let flags = parameters[2].uint64Value
        let supported: UInt64 = 0x1F0000  // Caps Lock, Shift, Control, Option, Command
        guard flags & ~supported == 0 else { return nil }
        return SpaceShortcut(keyCode: UInt16(code), flags: flags)
    }
}

public enum SpaceAction: CaseIterable {
    case switchSpace, moveWindow
}

/// The same key family switches Spaces, or moves a window with Shift added.
public enum ShortcutPreset: String, CaseIterable {
    case controlArrows, optionBrackets, controlOptionBrackets

    public func shortcut(for direction: Direction, action: SpaceAction) -> SpaceShortcut {
        let code: UInt16
        let flags: UInt64
        switch self {
        case .controlArrows:
            code = direction == .previous ? 123 : 124
            flags = 0x40000
        case .optionBrackets:
            code = direction == .previous ? 33 : 30
            flags = 0x80000
        case .controlOptionBrackets:
            code = direction == .previous ? 33 : 30
            flags = 0xC0000
        }
        return SpaceShortcut(keyCode: code, flags: flags | (action == .moveWindow ? 0x20000 : 0))
    }

    public func label(for direction: Direction, action: SpaceAction) -> String {
        let modifiers: String
        switch self {
        case .controlArrows: modifiers = "⌃"
        case .optionBrackets: modifiers = "⌥"
        case .controlOptionBrackets: modifiers = "⌃⌥"
        }
        let key =
            self == .controlArrows
            ? (direction == .previous ? "←" : "→")
            : (direction == .previous ? "[" : "]")
        return modifiers + (action == .moveWindow ? "⇧" : "") + key
    }

    public func label(for action: SpaceAction) -> String {
        Direction.allCases.map { label(for: $0, action: action) }.joined(separator: " / ")
    }
}

/// Number-row shortcuts use the same physical US-layout positions as bracket presets.
public enum JumpShortcutPreset: String, CaseIterable {
    case controlNumbers, optionNumbers, controlOptionNumbers, off

    private var modifiers: String {
        switch self {
        case .off: return ""
        case .controlNumbers: return "⌃"
        case .optionNumbers: return "⌥"
        case .controlOptionNumbers: return "⌃⌥"
        }
    }

    public var label: String { self == .off ? "Off" : "\(modifiers)1–9" }

    public var bindings: [(shortcut: SpaceShortcut, label: String)] {
        let flags: UInt64
        switch self {
        case .off: return []
        case .controlNumbers: flags = 0x40000
        case .optionNumbers: flags = 0x80000
        case .controlOptionNumbers: flags = 0xC0000
        }
        let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        return codes.enumerated().map { index, code in
            (SpaceShortcut(keyCode: code, flags: flags), "\(modifiers)\(index + 1)")
        }
    }
}

/// macOS preferences store overrides, not necessarily every built-in shortcut.
/// Missing Space-switch entries retain their enabled Control-arrow defaults.
public func resolvingDefaultSpaceShortcuts(in hotkeys: [String: Any]) -> [String: Any] {
    var resolved = hotkeys
    for (id, code, flags): (String, Int, UInt64) in [
        ("79", 123, 0x40000), ("80", 123, 0x60000),
        ("81", 124, 0x40000), ("82", 124, 0x60000),
    ] {
        var entry: [String: Any] = [
            "enabled": true,
            "value": ["parameters": [65535, code, NSNumber(value: flags)], "type": "standard"],
        ]
        if let configured = hotkeys[id] as? [String: Any] {
            entry.merge(configured) { _, configured in configured }
        }
        resolved[id] = entry
    }
    return resolved
}

/// Find configured overlaps, including hidden Shift variants (IDs 80/82).
/// Preferences do not prove that macOS will intercept these keys at runtime.
public func systemConflicts(
    for preset: ShortcutPreset,
    action: SpaceAction,
    in hotkeys: [String: Any]
) -> [String] {
    systemConflicts(
        for: Direction.allCases.map { preset.shortcut(for: $0, action: action) },
        in: hotkeys
    )
}

public func systemConflicts(for shortcuts: [SpaceShortcut], in hotkeys: [String: Any]) -> [String] {
    return hotkeys.compactMap { id, raw in
        guard let entry = raw as? [String: Any],
            (entry["enabled"] as? NSNumber)?.boolValue == true,
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [NSNumber], parameters.count == 3,
            shortcuts.contains(where: {
                Int($0.keyCode) == parameters[1].intValue && $0.flags == parameters[2].uint64Value
            })
        else { return nil }
        return id
    }.sorted()
}
