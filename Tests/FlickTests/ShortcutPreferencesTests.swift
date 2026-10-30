import FlickCore
import Foundation
import Testing

@testable import Flick

struct ShortcutPreferencesTests {
    private func withPreferences(_ body: (ShortcutPreferences) -> Void) {
        let suite = "Flick.ShortcutPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(ShortcutPreferences(defaults: defaults))
    }

    @Test func freshAndUnknownPreferencesDefaultToOptionBrackets() {
        withPreferences { preferences in
            #expect(preferences.movePreset == .optionBrackets)
            #expect(preferences.switchPreset == .optionBrackets)
            #expect(preferences.switchingEnabled)
            preferences.defaults.set("unknown", forKey: "moveShortcutPreset")
            preferences.defaults.set("unknown", forKey: "switchShortcutPreset")
            #expect(preferences.movePreset == .optionBrackets)
            #expect(preferences.switchPreset == .optionBrackets)
        }
    }

    @Test func selectionsPersistIndependentlyAndPreserveDisabledSwitching() {
        withPreferences { preferences in
            for move in ShortcutPreset.allCases {
                for switching in ShortcutPreset.allCases {
                    preferences.movePreset = move
                    preferences.switchPreset = switching
                    preferences.switchingEnabled = false
                    let reloaded = ShortcutPreferences(defaults: preferences.defaults)
                    #expect(reloaded.movePreset == move)
                    #expect(reloaded.switchPreset == switching)
                    #expect(!reloaded.switchingEnabled)
                }
            }
            preferences.switchingEnabled = true
            #expect(ShortcutPreferences(defaults: preferences.defaults).switchingEnabled)
        }
    }

    @Test func legacyMovePreferencesKeepTheirKeyFamily() {
        withPreferences { preferences in
            for (saved, expected): (String, ShortcutPreset) in [
                ("optionShift", .optionBrackets),
                ("controlOption", .controlOptionBrackets),
                ("controlOptionShift", .controlOptionBrackets),
            ] {
                preferences.defaults.set(saved, forKey: "moveShortcutPreset")
                #expect(preferences.movePreset == expected)
                #expect(
                    preferences.movePreset.shortcut(for: .previous, action: .moveWindow).flags
                        == (expected == .optionBrackets ? 0xA0000 : 0xE0000)
                )
                #expect(preferences.switchPreset == .optionBrackets)
            }
        }
    }
}
