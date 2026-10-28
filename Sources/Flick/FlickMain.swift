import AppKit
import ApplicationServices
import FlickCore

@main
struct FlickMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            print("Flick diagnostics (no windows or system settings are changed)")
            print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("Accessibility: \(AXIsProcessTrusted() ? "allowed" : "not granted")")
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
