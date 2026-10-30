import FlickCore
import Foundation

func symbolicHotkeys() -> [String: Any] {
    // Reload on registration/menu open; settings changes need no app restart.
    CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
    let configured =
        CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] ?? [:]
    return resolvingDefaultSpaceShortcuts(in: configured)
}
