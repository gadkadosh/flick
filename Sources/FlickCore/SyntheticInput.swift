import CoreGraphics

/// Event construction only. Keeping posting in the mover lets tests inspect
/// exact flags without generating input or moving any windows.
public enum SyntheticInput {
    public static func makeSource() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        // No inherited hardware modifiers and no extra hardware-suppression tail.
        source.localEventsSuppressionInterval = 0
        return source
    }

    public static func keyStroke(_ shortcut: SpaceShortcut, source: CGEventSource) -> (down: CGEvent, up: CGEvent)? {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else { return nil }
        // Use only Mission Control's modifiers, not the move shortcut's held
        // Option/Shift. Do not synthesize releases of the user's modifier keys.
        down.flags = CGEventFlags(rawValue: shortcut.flags)
        up.flags = CGEventFlags(rawValue: shortcut.flags)
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        return (down, up)
    }

    public static func mouse(_ type: CGEventType, at point: CGPoint, source: CGEventSource) -> CGEvent? {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.flags = [] // A normal title-bar drag, even with hardware modifiers held.
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }
}

public enum MoveTiming {
    public static let pressToDrag = 0.02
    public static let dragToSwitch = 0.02
    public static let dropToVerify = 0.05
    public static let minimumSwitchDuration = 0.65

    /// Time already spent waiting for the Space notification counts toward
    /// animation settling; do not add another full delay after it arrives.
    public static func remainingSwitchDelay(requestedAt: Double, now: Double) -> Double {
        max(0, minimumSwitchDuration - max(0, now - requestedAt))
    }
}

/// Carbon may repeat pressed events while the bracket key is down. Modifiers
/// can remain held between distinct bracket presses without retriggering a move.
public struct HotKeyPressTracker {
    private var pressed: Set<UInt32> = []
    public init() {}
    public mutating func press(_ id: UInt32) -> Bool { pressed.insert(id).inserted }
    public mutating func release(_ id: UInt32) { pressed.remove(id) }
}
