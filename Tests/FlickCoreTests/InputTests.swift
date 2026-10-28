import CoreGraphics
import Testing

@testable import FlickCore

struct InputTests {
    @Test func isolatedSourceHasNoSuppressionTail() throws {
        let source = try #require(SyntheticInput.makeSource())
        #expect(source.sourceStateID != .combinedSessionState)
        #expect(source.sourceStateID != .hidSystemState)
        #expect(source.localEventsSuppressionInterval == 0)
    }

    @Test func switchingEventsUseOnlyConfiguredModifiers() throws {
        let source = try #require(SyntheticInput.makeSource())
        let shortcut = SpaceShortcut(keyCode: 30, flags: CGEventFlags.maskAlternate.rawValue)
        let events = try #require(SyntheticInput.keyStroke(shortcut, source: source))
        #expect(events.down.type == .keyDown)
        #expect(events.up.type == .keyUp)
        #expect(events.down.flags == .maskAlternate)
        #expect(events.up.flags == .maskAlternate)
        #expect(!events.down.flags.contains(.maskShift))
        #expect(events.down.getIntegerValueField(.keyboardEventKeycode) == 30)
        #expect(events.down.getIntegerValueField(.keyboardEventAutorepeat) == 0)
    }

    @Test func mouseEventsAreUnmodified() throws {
        let source = try #require(SyntheticInput.makeSource())
        for type: CGEventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved] {
            let event = try #require(
                SyntheticInput.mouse(type, at: CGPoint(x: 50, y: 40), source: source)
            )
            #expect(event.flags.isEmpty)
            #expect(event.type == type)
            #expect(event.location == CGPoint(x: 50, y: 40))
        }
    }

    @Test func repeatedHotkeyWaitsForReleaseButOtherBracketCanBePressed() {
        var tracker = HotKeyPressTracker()
        var accepted = [tracker.press(1), tracker.press(1), tracker.press(2)]
        tracker.release(1)
        accepted.append(tracker.press(1))
        accepted.append(tracker.press(2))
        tracker.release(2)
        accepted.append(tracker.press(2))
        #expect(accepted == [true, false, true, true, false, true])
    }

    @Test func animationWaitCountsTimeSpentWaitingForNotification() {
        #expect(abs(MoveTiming.remainingSwitchDelay(requestedAt: 10, now: 10.4) - 0.25) < 0.001)
        #expect(MoveTiming.remainingSwitchDelay(requestedAt: 10, now: 11) == 0)
        #expect(MoveTiming.remainingSwitchDelay(requestedAt: 10, now: 10) == 0.65)
        #expect(MoveTiming.pressToDrag + MoveTiming.dragToSwitch <= 0.05)
    }
}
