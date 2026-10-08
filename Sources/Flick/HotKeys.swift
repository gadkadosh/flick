import AppKit
import Carbon
import FlickCore

@MainActor
final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var presses = HotKeyPressTracker()
    var onMove: ((Direction) -> Void)?

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x464C494B else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            // Carbon invokes this handler on the main application event loop.
            MainActor.assumeIsolated {
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    owner.presses.release(id.id)
                } else if owner.presses.press(id.id) {
                    owner.onMove?(id.id == 1 ? .previous : .next)
                }
            }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ preset: MoveShortcutPreset) throws {
        unregister()
        guard handler != nil else {
            throw FlickError.message("Could not install the macOS hotkey event handler.")
        }
        var modifiers: UInt32 = UInt32(optionKey)
        if preset != .controlOption { modifiers |= UInt32(shiftKey) }
        if preset != .optionShift { modifiers |= UInt32(controlKey) }
        for (index, direction) in Direction.allCases.enumerated() {
            var ref: EventHotKeyRef?
            let shortcut = preset.shortcut(for: direction)
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), modifiers,
                                            EventHotKeyID(signature: 0x464C494B, id: UInt32(index + 1)),
                                            GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                unregister()
                throw FlickError.message("Could not register \(preset.label(for: direction)) (macOS error \(status)). Choose another shortcut preset in Flick's menu.")
            }
            refs.append(ref)
        }
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        presses = HotKeyPressTracker()
    }

    func stop() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

struct FlickError: LocalizedError {
    let message: String
    static func message(_ text: String) -> FlickError { FlickError(message: text) }
    var errorDescription: String? { message }
}

func symbolicHotkeys() -> [String: Any] {
    // Reload at every move: changing System Settings must not require restarting Flick.
    CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
    return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                    "com.apple.symbolichotkeys" as CFString) as? [String: Any] ?? [:]
}
