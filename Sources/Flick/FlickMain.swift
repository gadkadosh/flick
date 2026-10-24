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
            let switchKeys = HotKeys(signature: 0x464C_5357)
            do {
                try switchKeys.registerSpaceSwitches()
                print("Switch ⌃← / ⌃→: registration OK")
            } catch { print(error.localizedDescription) }
            switchKeys.stop()
            let switchConflicts = systemConflicts(
                for: Direction.allCases.map { SpaceShortcut.switchShortcut(for: $0) },
                in: settings
            )
            if !switchConflicts.isEmpty {
                print("  Switch system overlaps: \(switchConflicts.joined(separator: ", "))")
            }
            for preset in MoveShortcutPreset.allCases {
                let keys = HotKeys()
                do {
                    try keys.register(preset)
                    print("Move \(preset.modifiersLabel)[/]: registration OK")
                } catch { print(error.localizedDescription) }
                keys.stop()
                let conflicts = systemConflicts(for: preset, in: settings)
                if !conflicts.isEmpty {
                    print("  System overlaps: \(conflicts.joined(separator: ", "))")
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
