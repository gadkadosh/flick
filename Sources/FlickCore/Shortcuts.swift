import Foundation

public enum Direction: CaseIterable, Hashable {
    case previous, next
    public var opposite: Direction { self == .previous ? .next : .previous }
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

    public static func read(direction: Direction, from hotkeys: [String: Any]) -> SpaceShortcut? {
        guard let entry = hotkeys[direction.symbolicID] as? [String: Any],
              (entry["enabled"] as? NSNumber)?.boolValue == true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber],
              parameters.count == 3 else { return nil }
        let code = parameters[1].intValue
        guard (0..<128).contains(code) else { return nil }
        // Reject unknown modifier bits rather than synthesize a different shortcut.
        let flags = parameters[2].uint64Value
        let supported: UInt64 = 0x1F0000 // Caps Lock, Shift, Control, Option, Command
        guard flags & ~supported == 0 else { return nil }
        return SpaceShortcut(keyCode: UInt16(code), flags: flags)
    }
}

public enum MoveShortcutPreset: String, CaseIterable {
    case optionShift, controlOption, controlOptionShift

    public var modifiersLabel: String {
        switch self {
        case .optionShift: return "⌥⇧"
        case .controlOption: return "⌃⌥"
        case .controlOptionShift: return "⌃⌥⇧"
        }
    }

    public var quartzFlags: UInt64 {
        switch self {
        case .optionShift: return 0xA0000
        case .controlOption: return 0xC0000
        case .controlOptionShift: return 0xE0000
        }
    }

    public func shortcut(for direction: Direction) -> SpaceShortcut {
        SpaceShortcut(keyCode: direction == .previous ? 33 : 30, flags: quartzFlags)
    }

    public func label(for direction: Direction) -> String {
        modifiersLabel + (direction == .previous ? "[" : "]")
    }
}

/// Detect an exact conflict with a system shortcut (including macOS's implicit
/// Shift variants, IDs 80/82). Never silently change the user's system settings.
public func systemConflicts(for preset: MoveShortcutPreset, in hotkeys: [String: Any]) -> [String] {
    let shortcuts = Direction.allCases.map { preset.shortcut(for: $0) }
    return hotkeys.compactMap { id, raw in
        guard let entry = raw as? [String: Any],
              (entry["enabled"] as? NSNumber)?.boolValue == true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], parameters.count == 3,
              shortcuts.contains(where: {
                  Int($0.keyCode) == parameters[1].intValue && $0.flags == parameters[2].uint64Value
              }) else { return nil }
        return id
    }.sorted()
}
