import AppKit
import ApplicationServices
import FlickCore
import SkyLightBridge

@main
struct FlickMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            print("Flick diagnostics (no windows or system settings are changed)")
            print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("Accessibility: \(AXIsProcessTrusted() ? "allowed" : "not granted")")
            print(
                "Direct Space operations: \(FlickSkyLightAvailable() ? "available (runtime symbols found; no move attempted)" : "unavailable")"
            )
            do {
                let backend = SkyLight()
                let displayID = try backend.activeDisplayID()
                let displays = try backend.displays()
                print(
                    "Active display: \(displayID) (layout match: \(displays.contains { $0.id == displayID }))"
                )
            } catch { print(error.localizedDescription) }
            let settings = symbolicHotkeys()
            for direction in Direction.allCases {
                if let shortcut = SpaceShortcut.read(direction: direction, from: settings) {
                    print(
                        "Switch \(direction.label): keyCode=\(shortcut.keyCode), flags=0x\(String(shortcut.flags, radix: 16))"
                    )
                } else {
                    print("Switch \(direction.label): disabled or unsupported")
                }
            }
            for action in SpaceAction.allCases {
                let name = action == .moveWindow ? "Move" : "Switch"
                for preset in ShortcutPreset.allCases {
                    let keys = HotKeys()
                    do {
                        try keys.register(preset, action: action)
                        print("\(name) \(preset.label(for: action)): registration OK")
                    } catch { print(error.localizedDescription) }
                    keys.stop()
                    let conflicts = systemConflicts(for: preset, action: action, in: settings)
                    if !conflicts.isEmpty {
                        print("  Possible system overlaps: \(conflicts.joined(separator: ", "))")
                    }
                }
            }
            for preset in JumpShortcutPreset.allCases where preset != .off {
                let keys = HotKeys()
                do {
                    try keys.register(preset)
                    print("Jump \(preset.label): registration OK")
                } catch { print(error.localizedDescription) }
                keys.stop()
                let conflicts = systemConflicts(for: preset.bindings.map(\.shortcut), in: settings)
                if !conflicts.isEmpty {
                    print("  Possible system overlaps: \(conflicts.joined(separator: ", "))")
                }
            }
        } else {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}
