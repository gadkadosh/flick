import Foundation

public struct WindowIdentity: Hashable, Sendable {
    public let processID: Int32
    public let windowID: UInt32

    public init(processID: Int32, windowID: UInt32) {
        self.processID = processID
        self.windowID = windowID
    }
}

/// All rectangles use Core Graphics coordinates (origin at the main display's top left).
public struct WindowSwitchDisplay: Equatable, Sendable {
    public let id: String
    public let frame: CGRect
    public let spaceID: UInt64

    public init(id: String, frame: CGRect, spaceID: UInt64) {
        self.id = id
        self.frame = frame
        self.spaceID = spaceID
    }

    public static func containing(_ frame: CGRect, in displays: [Self]) -> Self? {
        displays.max { overlap(frame, $0.frame) < overlap(frame, $1.frame) }
            .flatMap { overlap(frame, $0.frame) > 0 ? $0 : nil }
    }

    private static func overlap(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

public struct WindowSwitchCandidate: Sendable {
    public let id: WindowIdentity
    public let frame: CGRect
    public let spaces: [UInt64]

    public init(id: WindowIdentity, frame: CGRect, spaces: [UInt64]) {
        self.id = id
        self.frame = frame
        self.spaces = spaces
    }

    public func belongs(to display: WindowSwitchDisplay, among displays: [WindowSwitchDisplay])
        -> Bool
    {
        spaces.contains(display.spaceID)
            && WindowSwitchDisplay.containing(frame, in: displays)?.id == display.id
    }
}

public struct WindowFocusHistory {
    private var recent: [WindowIdentity] = []

    public init() {}

    public mutating func record(_ id: WindowIdentity) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if recent.count > 512 { recent.removeLast(recent.count - 512) }
    }

    /// Unobserved windows retain the supplied front-to-back order.
    public func ordered(_ ids: [WindowIdentity]) -> [WindowIdentity] {
        let available = Set(ids)
        let known = recent.filter { available.contains($0) }
        let seen = Set(known)
        return known + ids.filter { !seen.contains($0) }
    }
}

public struct WindowSwitchSession {
    public let windows: [WindowIdentity]
    private(set) public var index: Int
    public var selected: WindowIdentity { windows[index] }

    public init?(windows: [WindowIdentity], focused: WindowIdentity?, backwards: Bool) {
        guard !windows.isEmpty else { return nil }
        self.windows = windows
        if let focused, let index = windows.firstIndex(of: focused) {
            self.index = index
            advance(backwards: backwards)
        } else {
            index = backwards ? windows.count - 1 : 0
        }
    }

    public mutating func advance(backwards: Bool) {
        index = (index + (backwards ? windows.count - 1 : 1)) % windows.count
    }
}

/// Keeps suppression paired through key-up, even when Option is released first.
public struct WindowSwitchKeys {
    public enum Command: Equatable, Sendable {
        case begin(backwards: Bool)
        case advance(backwards: Bool)
        case commit
        case cancel
    }

    public struct Result {
        public let suppress: Bool
        public let command: Command?
    }

    public private(set) var active = false
    private var swallowed: Set<UInt16> = []

    public init() {}

    public mutating func key(
        code: UInt16,
        down: Bool,
        option: Bool,
        shift: Bool,
        otherModifiers: Bool,
        pending: Bool = false
    ) -> Result {
        if !down {
            return Result(suppress: swallowed.remove(code) != nil, command: nil)
        }
        if code == 48 && option && !otherModifiers {
            swallowed.insert(code)
            let command: Command = active ? .advance(backwards: shift) : .begin(backwards: shift)
            active = true
            return Result(suppress: true, command: command)
        }
        if (active || pending) && code == 53 {
            swallowed.insert(code)
            return Result(suppress: true, command: end(.cancel))
        }
        // Do not leak auto-repeats of a consumed key after cancellation/release.
        if swallowed.contains(code) { return Result(suppress: true, command: nil) }
        return Result(suppress: false, command: (active || pending) ? end(.cancel) : nil)
    }

    public mutating func modifiers(option: Bool, otherModifiers: Bool, pending: Bool = false)
        -> Command?
    {
        guard active else { return pending && otherModifiers ? end(.cancel) : nil }
        if otherModifiers { return end(.cancel) }
        return option ? nil : end(.commit)
    }

    public mutating func cancel(pending: Bool = false) -> Command? {
        (active || pending) ? end(.cancel) : nil
    }

    public mutating func reset() {
        active = false
        swallowed.removeAll()
    }

    private mutating func end(_ command: Command) -> Command {
        active = false
        return command
    }
}
