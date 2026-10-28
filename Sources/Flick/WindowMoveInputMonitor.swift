import AppKit
import Carbon
import FlickCore

/// Focus changes caused by the Space transition itself are expected. Instead,
/// latch user intervention so restoring focus cannot conceal it from the queue.
@MainActor
final class WindowMoveInputMonitor {
    typealias StopTap = @MainActor () -> Void
    typealias StartTap = @MainActor (WindowMoveInputMonitor) throws -> StopTap

    private let shortcuts: [SpaceShortcut]
    private let interrupt: @MainActor () -> Void
    private let isSecureInputEnabled: @MainActor () -> Bool
    private var keyboardUnavailable = false
    private var stopTap: StopTap?
    private var securityTimer: Timer?

    init(
        shortcuts: [SpaceShortcut], interrupt: @escaping @MainActor () -> Void,
        isSecureInputEnabled: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() },
        startTap: StartTap = WindowMoveInputMonitor.installTap
    ) throws {
        self.shortcuts = shortcuts
        self.interrupt = interrupt
        self.isSecureInputEnabled = isSecureInputEnabled
        try checkAvailability()
        stopTap = try startTap(self)
        // Secure Event Input can suppress keys without disabling the tap.
        // Remember it even if secure entry ends before confirmation finishes.
        let timer = Timer(timeInterval: 0.002, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { try? self?.checkAvailability() }
        }
        securityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func checkAvailability() throws {
        if !keyboardUnavailable && isSecureInputEnabled() {
            keyboardUnavailable = true
            interrupt()
        }
        guard !keyboardUnavailable else {
            throw FlickError.message("Secure Keyboard Entry prevents safe keyboard observation. Try again after secure entry ends; remaining queued moves were discarded.")
        }
    }

    func receive(type: CGEventType, event: CGEvent) {
        if Self.interrupts(type: type, event: event, shortcuts: shortcuts) { interrupt() }
    }

    func stop() {
        securityTimer?.invalidate()
        securityTimer = nil
        stopTap?()
        stopTap = nil
    }

    private static func installTap(_ monitor: WindowMoveInputMonitor) throws -> StopTap {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                if let context {
                    let monitor = Unmanaged<WindowMoveInputMonitor>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { monitor.receive(type: type, event: event) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(monitor).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            throw FlickError.message("Could not observe input safely. Check Flick's Accessibility permission, then try again.")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return {
            CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    static func interrupts(type: CGEventType, event: CGEvent, shortcuts: [SpaceShortcut]) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .tapDisabledByTimeout, .tapDisabledByUserInput:
            return true
        case .keyDown:
            let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let flags = event.flags.intersection(modifiers).rawValue
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return !shortcuts.contains { Int64($0.keyCode) == code && $0.flags == flags }
        default:
            return false
        }
    }
}
