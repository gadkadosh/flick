import Foundation
import Testing

@testable import FlickCore

struct WindowSwitchTests {
    private let a = WindowIdentity(processID: 10, windowID: 1)
    private let b = WindowIdentity(processID: 10, windowID: 2)
    private let c = WindowIdentity(processID: 20, windowID: 3)
    private let displays = [
        WindowSwitchDisplay(
            id: "left",
            frame: CGRect(x: -1200, y: 200, width: 1200, height: 900),
            spaceID: 1
        ),
        WindowSwitchDisplay(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            spaceID: 2
        ),
        WindowSwitchDisplay(
            id: "above",
            frame: CGRect(x: 0, y: -900, width: 1200, height: 900),
            spaceID: 3
        ),
    ]

    @Test func displayUsesLargestIntersectionNotPointerOrWindowOrigin() {
        #expect(
            WindowSwitchDisplay.containing(
                CGRect(x: -100, y: 250, width: 800, height: 500),
                in: displays
            )?.id == "main"
        )
        #expect(
            WindowSwitchDisplay.containing(
                CGRect(x: -1000, y: 250, width: 1100, height: 500),
                in: displays
            )?.id == "left"
        )
        #expect(
            WindowSwitchDisplay.containing(
                CGRect(x: 100, y: -700, width: 600, height: 500),
                in: displays
            )?.id == "above"
        )
        #expect(
            WindowSwitchDisplay.containing(
                CGRect(x: 5000, y: 0, width: 100, height: 100),
                in: displays
            ) == nil
        )
    }

    @Test func bothDisplayAndVisibleSpaceMustMatchIncludingPinnedWindows() {
        let main = displays[1]
        let frame = CGRect(x: 200, y: 200, width: 600, height: 500)
        #expect(
            WindowSwitchCandidate(id: a, frame: frame, spaces: [2]).belongs(
                to: main,
                among: displays
            )
        )
        #expect(
            !WindowSwitchCandidate(id: a, frame: frame, spaces: [99]).belongs(
                to: main,
                among: displays
            )
        )
        #expect(
            WindowSwitchCandidate(id: a, frame: frame, spaces: [2, 99]).belongs(
                to: main,
                among: displays
            )
        )
        #expect(
            !WindowSwitchCandidate(
                id: a,
                frame: CGRect(x: -900, y: 300, width: 500, height: 400),
                spaces: [2]
            )
            .belongs(to: main, among: displays)
        )
    }

    @Test func historyKeepsIndividualWindowsAndPreservesUnknownWindowOrder() {
        var history = WindowFocusHistory()
        history.record(b)
        history.record(c)
        history.record(b)
        #expect(history.ordered([a, b, c]) == [b, c, a])
        #expect(history.ordered([a, c]) == [c, a])
        #expect(history.ordered([a]) == [a])
        #expect(history.ordered([]).isEmpty)
    }

    @Test func cyclingStartsAfterFocusedWindowAndWrapsBothWays() throws {
        var session = try #require(
            WindowSwitchSession(windows: [a, b, c], focused: a, backwards: false)
        )
        #expect(session.selected == b)
        session.advance(backwards: false)
        #expect(session.selected == c)
        session.advance(backwards: false)
        #expect(session.selected == a)
        session.advance(backwards: true)
        #expect(session.selected == c)
        #expect(
            WindowSwitchSession(windows: [a, b, c], focused: a, backwards: true)?.selected == c
        )
        #expect(
            WindowSwitchSession(windows: [a, b, c], focused: nil, backwards: false)?.selected == a
        )
        #expect(
            WindowSwitchSession(windows: [a, b, c], focused: nil, backwards: true)?.selected == c
        )
        #expect(WindowSwitchSession(windows: [a], focused: a, backwards: false)?.selected == a)
        #expect(WindowSwitchSession(windows: [], focused: a, backwards: false) == nil)
    }

    @Test func optionTabReleaseCommitsOnceAndConsumesTrailingTabUp() {
        var keys = WindowSwitchKeys()
        let begin = keys.key(
            code: 48,
            down: true,
            option: true,
            shift: false,
            otherModifiers: false
        )
        #expect(begin.suppress)
        #expect(begin.command == .begin(backwards: false))
        #expect(
            keys.key(code: 48, down: true, option: true, shift: true, otherModifiers: false).command
                == .advance(backwards: true)
        )
        #expect(keys.modifiers(option: false, otherModifiers: false) == .commit)
        #expect(keys.modifiers(option: false, otherModifiers: false) == nil)
        #expect(
            keys.key(code: 48, down: false, option: false, shift: false, otherModifiers: false)
                .suppress
        )
        #expect(
            !keys.key(code: 48, down: false, option: false, shift: false, otherModifiers: false)
                .suppress
        )
        #expect(!keys.active)
    }

    @Test func escapeCancelsWithoutLeakingEscapeOrCommittingOnRelease() {
        var keys = WindowSwitchKeys()
        _ = keys.key(code: 48, down: true, option: true, shift: false, otherModifiers: false)
        let escape = keys.key(
            code: 53,
            down: true,
            option: true,
            shift: false,
            otherModifiers: false
        )
        #expect(escape.suppress)
        #expect(escape.command == .cancel)
        for _ in 0..<3 {
            let repeatTab = keys.key(
                code: 48,
                down: true,
                option: true,
                shift: false,
                otherModifiers: false
            )
            #expect(repeatTab.suppress)
            #expect(repeatTab.command == nil)
        }
        #expect(!keys.active)
        #expect(keys.modifiers(option: false, otherModifiers: false) == nil)
        #expect(
            keys.key(code: 53, down: false, option: false, shift: false, otherModifiers: false)
                .suppress
        )
        #expect(
            keys.key(code: 48, down: false, option: false, shift: false, otherModifiers: false)
                .suppress
        )
    }

    @Test func unrelatedInputCancelsButIsNotSwallowedAndCommandTabIsUntouched() {
        var keys = WindowSwitchKeys()
        #expect(
            !keys.key(code: 48, down: true, option: false, shift: false, otherModifiers: true)
                .suppress
        )
        _ = keys.key(code: 48, down: true, option: true, shift: false, otherModifiers: false)
        let typing = keys.key(
            code: 0,
            down: true,
            option: true,
            shift: false,
            otherModifiers: false
        )
        #expect(!typing.suppress)
        #expect(typing.command == .cancel)
        #expect(keys.modifiers(option: false, otherModifiers: false) == nil)
        _ = keys.key(code: 48, down: false, option: false, shift: false, otherModifiers: false)
        _ = keys.key(code: 48, down: true, option: true, shift: false, otherModifiers: false)
        #expect(keys.modifiers(option: true, otherModifiers: true) == .cancel)
        #expect(keys.cancel() == nil)
    }
}
