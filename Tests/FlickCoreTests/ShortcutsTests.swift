import Carbon
import CoreGraphics
import Foundation
import Testing

@testable import FlickCore

struct ShortcutsTests {
    private func entry(enabled: Bool = true, code: Int = 33, flags: UInt64 = 0x80000) -> [String:
        Any]
    {
        [
            "enabled": enabled,
            "value": [
                "parameters": [NSNumber(value: 91), NSNumber(value: code), NSNumber(value: flags)]
            ],
        ]
    }

    @Test func readOptionBracketShortcut() {
        let settings = ["79": entry(), "81": entry(code: 30)]
        #expect(
            SpaceShortcut.read(direction: .previous, from: settings)
                == SpaceShortcut(keyCode: 33, flags: 0x80000)
        )
        #expect(SpaceShortcut.read(direction: .next, from: settings)?.keyCode == 30)
    }

    @Test func disabledMissingAndMalformedShortcuts() {
        #expect(SpaceShortcut.read(direction: .previous, from: [:]) == nil)
        #expect(
            SpaceShortcut.read(direction: .previous, from: ["79": entry(enabled: false)]) == nil
        )
        #expect(
            SpaceShortcut.read(
                direction: .previous,
                from: ["79": ["enabled": true, "value": ["parameters": [1]]]]
            ) == nil
        )
        #expect(SpaceShortcut.read(direction: .previous, from: ["79": entry(code: 65535)]) == nil)
        #expect(
            SpaceShortcut.read(direction: .previous, from: ["79": entry(flags: 0x800000)]) == nil
        )
    }

    @Test func controlArrowShortcut() {
        let settings = ["79": entry(code: 123, flags: 0x40000)]
        #expect(
            SpaceShortcut.read(direction: .previous, from: settings)
                == SpaceShortcut(keyCode: 123, flags: 0x40000)
        )
    }

    @Test func implicitShiftOverlaps() {
        let settings = [
            "79": entry(), "80": entry(flags: 0xA0000), "82": entry(code: 30, flags: 0xA0000),
        ]
        #expect(
            systemConflicts(for: .optionBrackets, action: .moveWindow, in: settings) == [
                "80", "82",
            ]
        )
        #expect(systemConflicts(for: .optionBrackets, action: .switchSpace, in: settings) == ["79"])
        #expect(
            systemConflicts(for: .controlOptionBrackets, action: .moveWindow, in: settings).isEmpty
        )
    }

    @Test func disabledOverlapIgnored() {
        #expect(
            systemConflicts(
                for: .optionBrackets,
                action: .moveWindow,
                in: ["80": entry(enabled: false, flags: 0xA0000)]
            ).isEmpty
        )
    }

    @Test func pairedPresetsUseMatchingLabelsEventAndRegistrationModifiers() {
        let expected: [(ShortcutPreset, UInt16, UInt16, UInt64, UInt32, String, String)] = [
            (.controlArrows, 123, 124, 0x40000, UInt32(controlKey), "⌃", "←→"),
            (.optionBrackets, 33, 30, 0x80000, UInt32(optionKey), "⌥", "[]"),
            (.controlOptionBrackets, 33, 30, 0xC0000, UInt32(controlKey | optionKey), "⌃⌥", "[]"),
        ]
        #expect(expected.count == ShortcutPreset.allCases.count)
        for (preset, previous, next, flags, carbon, modifiers, keys) in expected {
            for action in SpaceAction.allCases {
                let moving = action == .moveWindow
                for direction in Direction.allCases {
                    let shortcut = preset.shortcut(for: direction, action: action)
                    #expect(shortcut.keyCode == (direction == .previous ? previous : next))
                    #expect(shortcut.flags == flags | (moving ? 0x20000 : 0))
                    #expect(shortcut.carbonModifiers == carbon | (moving ? UInt32(shiftKey) : 0))
                    let key = direction == .previous ? keys.first! : keys.last!
                    #expect(
                        preset.label(for: direction, action: action)
                            == modifiers + (moving ? "⇧" : "") + String(key)
                    )
                }
                #expect(
                    preset.label(for: action)
                        == preset.label(for: .previous, action: action) + " / "
                        + preset.label(for: .next, action: action)
                )
            }
        }
    }

    @Test func independentSelectionsNeverUseTheSameCombination() {
        for move in ShortcutPreset.allCases {
            for switching in ShortcutPreset.allCases {
                for direction in Direction.allCases {
                    #expect(
                        move.shortcut(for: direction, action: .moveWindow)
                            != switching.shortcut(for: direction, action: .switchSpace)
                    )
                }
            }
        }
    }

    @Test func missingSystemOverridesKeepMacOSControlArrowDefaults() {
        let defaults = resolvingDefaultSpaceShortcuts(in: [:])
        #expect(
            systemConflicts(for: .controlArrows, action: .switchSpace, in: defaults) == [
                "79", "81",
            ]
        )
        #expect(
            systemConflicts(for: .controlArrows, action: .moveWindow, in: defaults) == ["80", "82"]
        )
        #expect(
            SpaceShortcut.read(direction: .previous, from: defaults)
                == ShortcutPreset.controlArrows.shortcut(for: .previous, action: .switchSpace)
        )
        let disabled = resolvingDefaultSpaceShortcuts(in: [
            "79": ["enabled": false], "81": ["enabled": false],
        ])
        #expect(systemConflicts(for: .controlArrows, action: .switchSpace, in: disabled).isEmpty)
        let reassigned = resolvingDefaultSpaceShortcuts(in: ["79": entry(), "81": entry(code: 30)])
        #expect(systemConflicts(for: .controlArrows, action: .switchSpace, in: reassigned).isEmpty)
        #expect(
            systemConflicts(for: .optionBrackets, action: .switchSpace, in: reassigned) == [
                "79", "81",
            ]
        )
    }

    @Test func eachQuartzModifierConvertsToItsCarbonEquivalent() {
        let expected: [(CGEventFlags, Int)] = [
            (.maskAlphaShift, alphaLock), (.maskShift, shiftKey),
            (.maskControl, controlKey), (.maskAlternate, optionKey),
            (.maskCommand, cmdKey),
        ]
        #expect(SpaceShortcut(keyCode: 33, flags: 0).carbonModifiers == 0)
        for (flag, modifier) in expected {
            let shortcut = SpaceShortcut(keyCode: 33, flags: flag.rawValue)
            #expect(shortcut.carbonModifiers == UInt32(modifier))
        }
    }
}
