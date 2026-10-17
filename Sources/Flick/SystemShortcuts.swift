import Foundation

func symbolicHotkeys() -> [String: Any] {
    // Reload at every move: changing System Settings must not require restarting Flick.
    CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
    return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                    "com.apple.symbolichotkeys" as CFString) as? [String: Any] ?? [:]
}
