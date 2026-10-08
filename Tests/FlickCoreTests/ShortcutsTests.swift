import Foundation
import Testing
@testable import FlickCore

struct ShortcutsTests {
    private func entry(enabled: Bool = true, code: Int = 33, flags: UInt64 = 0x80000) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [NSNumber(value: 91), NSNumber(value: code), NSNumber(value: flags)]]]
    }

    @Test func readOptionBracketShortcut() {
        let settings = ["79": entry(), "81": entry(code: 30)]
        #expect(SpaceShortcut.read(direction: .previous, from: settings) == SpaceShortcut(keyCode: 33, flags: 0x80000))
        #expect(SpaceShortcut.read(direction: .next, from: settings)?.keyCode == 30)
    }

    @Test func disabledMissingAndMalformedShortcuts() {
        #expect(SpaceShortcut.read(direction: .previous, from: [:]) == nil)
        #expect(SpaceShortcut.read(direction: .previous, from: ["79": entry(enabled: false)]) == nil)
        #expect(SpaceShortcut.read(direction: .previous, from: ["79": ["enabled": true, "value": ["parameters": [1]]]]) == nil)
        #expect(SpaceShortcut.read(direction: .previous, from: ["79": entry(code: 65535)]) == nil)
        #expect(SpaceShortcut.read(direction: .previous, from: ["79": entry(flags: 0x800000)]) == nil)
    }

    @Test func controlArrowShortcut() {
        let settings = ["79": entry(code: 123, flags: 0x40000)]
        #expect(SpaceShortcut.read(direction: .previous, from: settings) == SpaceShortcut(keyCode: 123, flags: 0x40000))
    }

    @Test func implicitShiftConflicts() {
        let settings = ["79": entry(), "80": entry(flags: 0xA0000), "82": entry(code: 30, flags: 0xA0000)]
        #expect(systemConflicts(for: .optionShift, in: settings) == ["80", "82"])
        #expect(systemConflicts(for: .controlOption, in: settings).isEmpty)
    }

    @Test func disabledConflictIgnored() {
        #expect(systemConflicts(for: .optionShift, in: ["80": entry(enabled: false, flags: 0xA0000)]).isEmpty)
    }

    @Test func presetsAndDirections() {
        #expect(Direction.previous.opposite == .next)
        #expect(Direction.next.opposite == .previous)
        for preset in MoveShortcutPreset.allCases {
            #expect(preset.shortcut(for: .previous).keyCode == 33)
            #expect(preset.shortcut(for: .next).keyCode == 30)
            #expect(preset.quartzFlags != 0x80000)
        }
        #expect(MoveShortcutPreset.optionShift.label(for: .next) == "⌥⇧]")
        #expect(MoveShortcutPreset.controlOption.quartzFlags == 0xC0000)
    }
}
