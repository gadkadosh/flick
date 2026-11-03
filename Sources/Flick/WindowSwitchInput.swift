import AppKit
import Carbon
import FlickCore

@MainActor
final class WindowSwitchInput {
    var onCommand: ((WindowSwitchKeys.Command) -> Void)?
    var onFailure: ((String) -> Void)?
    var isBusy: () -> Bool = { false }
    private var generation = 0
    private var pendingDeliveries = 0
    private var pending: Bool { pendingDeliveries > 0 || isBusy() }
    private var keys = WindowSwitchKeys()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var securityTimer: Timer?
    private let isSecureInputEnabled: () -> Bool

    init(isSecureInputEnabled: @escaping () -> Bool = { IsSecureEventInputEnabled() }) {
        self.isSecureInputEnabled = isSecureInputEnabled
    }

    func start() throws {
        guard AXIsProcessTrusted() else {
            throw FlickError.message(
                "Window switching needs Accessibility permission. Grant it in Flick’s menu, then reopen the menu to retry."
            )
        }
        if let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            guard CGEvent.tapIsEnabled(tap: tap) else {
                throw FlickError.message(
                    "macOS disabled keyboard capture. Check Flick’s Accessibility permission."
                )
            }
            return
        }
        if tap != nil { stop() }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let owner = Unmanaged<WindowSwitchInput>.fromOpaque(context)
                        .takeUnretainedValue()
                    return MainActor.assumeIsolated {
                        owner.receive(type: type, event: event)
                            ? nil : Unmanaged.passUnretained(event)
                    }
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else {
            throw FlickError.message(
                "Could not capture ⌥Tab. Check Flick’s Accessibility permission, then reopen the menu to retry."
            )
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSecureInputEnabled() else { return }
                self.cancelForSecureInput()
            }
        }
        securityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func receive(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            keys.reset()
            deliver(.cancel)
            DispatchQueue.main.async { [weak self] in
                self?.onFailure?(
                    "Window switching was cancelled because keyboard capture was interrupted."
                )
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if isSecureInputEnabled() {
            cancelForSecureInput()
            return false
        }
        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let other = !flags.intersection([.maskCommand, .maskControl]).isEmpty
        switch type {
        case .keyDown, .keyUp:
            let result = keys.key(
                code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                down: type == .keyDown,
                option: option,
                shift: flags.contains(.maskShift),
                otherModifiers: other,
                pending: pending
            )
            if let command = result.command { deliver(command) }
            return result.suppress
        case .flagsChanged:
            if let command = keys.modifiers(option: option, otherModifiers: other, pending: pending)
            {
                deliver(command)
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if let command = keys.cancel(pending: pending) { deliver(command) }
        default: break
        }
        return false
    }

    private func cancelForSecureInput() {
        guard keys.cancel(pending: pending) != nil else { return }
        // Invalidate a begin/commit that may still be waiting for delivery.
        generation += 1
        pendingDeliveries = 0
        deliver(.cancel)
    }

    // Never enumerate windows or talk to another app inside the event-tap callback.
    private func deliver(_ command: WindowSwitchKeys.Command) {
        let token = generation
        pendingDeliveries += 1
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.pendingDeliveries -= 1
            self.onCommand?(command)
        }
    }

    func stop() {
        generation += 1
        pendingDeliveries = 0
        securityTimer?.invalidate()
        securityTimer = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        keys.reset()
        onCommand?(.cancel)
    }
}
