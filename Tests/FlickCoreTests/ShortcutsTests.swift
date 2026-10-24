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

    @Test func implicitShiftConflicts() {
        let settings = [
            "79": entry(), "80": entry(flags: 0xA0000), "82": entry(code: 30, flags: 0xA0000),
        ]
        #expect(systemConflicts(for: .optionShift, in: settings) == ["80", "82"])
        #expect(systemConflicts(for: .controlOption, in: settings).isEmpty)
    }

    @Test func disabledConflictIgnored() {
        #expect(
            systemConflicts(for: .optionShift, in: ["80": entry(enabled: false, flags: 0xA0000)])
                .isEmpty
        )
    }

    @Test func presetsUseMatchingEventAndRegistrationModifiers() {
        let expected: [(MoveShortcutPreset, UInt64, UInt32, String)] = [
            (.optionShift, 0xA0000, UInt32(optionKey | shiftKey), "⌥⇧"),
            (.controlOption, 0xC0000, UInt32(controlKey | optionKey), "⌃⌥"),
            (.controlOptionShift, 0xE0000, UInt32(controlKey | optionKey | shiftKey), "⌃⌥⇧"),
        ]
        #expect(expected.count == MoveShortcutPreset.allCases.count)
        for (preset, flags, modifiers, label) in expected {
            for direction in Direction.allCases {
                let shortcut = preset.shortcut(for: direction)
                #expect(shortcut.keyCode == (direction == .previous ? 33 : 30))
                #expect(shortcut.flags == flags)
                #expect(shortcut.carbonModifiers == modifiers)
                #expect(
                    preset.label(for: direction) == label + (direction == .previous ? "[" : "]")
                )
            }
        }
    }

    @Test func standaloneSwitchesUseControlArrowsAndDetectSystemConflicts() {
        let previous = SpaceShortcut.switchShortcut(for: .previous)
        let next = SpaceShortcut.switchShortcut(for: .next)
        #expect(previous.keyCode == 123)
        #expect(next.keyCode == 124)
        #expect(previous.carbonModifiers == UInt32(controlKey))
        #expect(next.carbonModifiers == UInt32(controlKey))
        let settings = [
            "79": entry(code: 123, flags: 0x40000),
            "81": entry(code: 124, flags: 0x40000),
            "82": entry(code: 124, flags: 0x60000),
        ]
        #expect(systemConflicts(for: [previous, next], in: settings) == ["79", "81"])
        #expect(
            systemConflicts(
                for: [previous, next],
                in: ["79": entry(enabled: false, code: 123, flags: 0x40000)]
            ).isEmpty
        )
        #expect(systemConflicts(for: .optionShift, in: settings).isEmpty)
    }

    @Test func missingSystemOverridesStillReserveDefaultControlArrows() {
        let switches = Direction.allCases.map { SpaceShortcut.switchShortcut(for: $0) }
        let defaults = resolvingDefaultSpaceShortcuts(in: [:])
        #expect(systemConflicts(for: switches, in: defaults) == ["79", "81"])
        #expect(SpaceShortcut.read(direction: .previous, from: defaults) == switches[0])
        let disabled = resolvingDefaultSpaceShortcuts(in: [
            "79": ["enabled": false], "81": ["enabled": false],
        ])
        #expect(systemConflicts(for: switches, in: disabled).isEmpty)
        let reassigned = resolvingDefaultSpaceShortcuts(in: ["79": entry(), "81": entry(code: 30)])
        #expect(systemConflicts(for: switches, in: reassigned).isEmpty)
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
