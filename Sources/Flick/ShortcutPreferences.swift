import FlickCore
import Foundation

struct ShortcutPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var movePreset: ShortcutPreset {
        get {
            let saved = defaults.string(forKey: "moveShortcutPreset") ?? ""
            if let preset = ShortcutPreset(rawValue: saved) { return preset }
            // Preserve legacy families. The old unshifted Control–Option move
            // preset now uses Shift, like every other move preset.
            switch saved {
            case "controlOption", "controlOptionShift": return .controlOptionBrackets
            default: return .optionBrackets
            }
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "moveShortcutPreset") }
    }

    var switchPreset: ShortcutPreset {
        get {
            ShortcutPreset(rawValue: defaults.string(forKey: "switchShortcutPreset") ?? "")
                ?? .optionBrackets
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "switchShortcutPreset") }
    }

    var switchingEnabled: Bool {
        get { defaults.object(forKey: "spaceSwitchingEnabled") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "spaceSwitchingEnabled") }
    }
}
