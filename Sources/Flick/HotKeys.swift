import AppKit
import Carbon
import FlickCore

@MainActor
protocol HotKeyRegistering: AnyObject {
    var onPress: ((Int) -> Void)? { get set }
    func register(_ preset: ShortcutPreset, action: SpaceAction) throws
    func register(_ preset: JumpShortcutPreset) throws
    func unregister()
    func stop()
}

@MainActor
final class HotKeys: HotKeyRegistering {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var presses = HotKeyPressTracker()
    /// Zero-based index into the registered bindings.
    var onPress: ((Int) -> Void)?
    private let signature: OSType

    init(signature: OSType = 0x464C_494B) {
        self.signature = signature
        var types = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
                guard result == noErr, id.signature == owner.signature,
                    id.id > 0, id.id <= owner.refs.count
                else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon invokes this handler on the main application event loop.
                MainActor.assumeIsolated {
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                        owner.presses.release(id.id)
                    } else if owner.presses.press(id.id) {
                        owner.onPress?(Int(id.id) - 1)
                    }
                }
                return noErr
            },
            types.count,
            &types,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    func register(_ preset: ShortcutPreset, action: SpaceAction) throws {
        try register(
            Direction.allCases.map {
                (preset.shortcut(for: $0, action: action), preset.label(for: $0, action: action))
            }
        )
    }

    func register(_ preset: JumpShortcutPreset) throws {
        try register(preset.bindings)
    }

    private func register(_ shortcuts: [(SpaceShortcut, String)]) throws {
        unregister()
        guard handler != nil else {
            throw FlickError.message("Could not install the macOS hotkey event handler.")
        }
        for (index, binding) in shortcuts.enumerated() {
            var ref: EventHotKeyRef?
            let (shortcut, label) = binding
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                shortcut.carbonModifiers,
                EventHotKeyID(signature: signature, id: UInt32(index + 1)),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            guard status == noErr, let ref else {
                unregister()
                throw FlickError.message(
                    "Could not register \(label) (macOS error \(status)). Check for shortcut conflicts in Flick and System Settings."
                )
            }
            refs.append(ref)
        }
    }

    func unregister() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        presses = HotKeyPressTracker()
    }

    func stop() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
