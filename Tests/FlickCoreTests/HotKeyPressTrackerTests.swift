import Testing

@testable import FlickCore

struct HotKeyPressTrackerTests {
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
}
