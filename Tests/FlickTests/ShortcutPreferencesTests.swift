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

    @Test func numberedJumpDefaultsToOffAndPersistsIndependently() {
        withPreferences { preferences in
            #expect(preferences.jumpPreset == .off)
            preferences.defaults.set("unknown", forKey: "jumpShortcutPreset")
            #expect(preferences.jumpPreset == .off)
            preferences.movePreset = .controlArrows
            preferences.switchPreset = .controlOptionBrackets
            preferences.switchingEnabled = false
            for preset in JumpShortcutPreset.allCases {
                preferences.jumpPreset = preset
                let reloaded = ShortcutPreferences(defaults: preferences.defaults)
                #expect(reloaded.jumpPreset == preset)
                #expect(reloaded.movePreset == .controlArrows)
                #expect(reloaded.switchPreset == .controlOptionBrackets)
                #expect(!reloaded.switchingEnabled)
            }
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
}
