import Testing

@testable import FlickCore

struct WindowMoveBurstTests {
    @Test func requestsAreAcceptedOnlyDuringHeldWindowPhase() {
        var burst = WindowMoveBurst()
        let beforeBegin = burst.enqueue(.next)
        burst.begin()
        let duringDrag = burst.enqueue(.next)
        burst.close()
        let afterDrop = burst.enqueue(.next)
        let next = burst.takeNext()
        #expect(!beforeBegin)
        #expect(duringDrag)
        #expect(!afterDrop)
        #expect(next == nil)
    }

    @Test func rapidPressesKeepFIFOOrderIncludingOppositeDirection() {
        var burst = WindowMoveBurst()
        burst.begin()
        let accepted = [burst.enqueue(.next), burst.enqueue(.next), burst.enqueue(.previous)]
        let consumed = [burst.takeNext(), burst.takeNext(), burst.takeNext(), burst.takeNext()]
        #expect(accepted == [true, true, true])
        #expect(consumed == [.next, .next, .previous, nil])
    }

    @Test func queueIsBoundedAndFreesCapacityAsStepsStart() {
        var burst = WindowMoveBurst()
        burst.begin()
        let accepted = (0..<(WindowMoveBurst.maximumPending + 2)).map { _ in burst.enqueue(.next) }
        #expect(accepted.filter { $0 }.count == WindowMoveBurst.maximumPending)
        #expect(burst.pendingCount == WindowMoveBurst.maximumPending)
        _ = burst.takeNext()
        let acceptedAfterConsumption = burst.enqueue(.previous)
        #expect(acceptedAfterConsumption)
        #expect(burst.pendingCount == WindowMoveBurst.maximumPending)
    }

    @Test func closingDiscardsAllRemainingRequests() {
        var burst = WindowMoveBurst()
        burst.begin()
        _ = burst.enqueue(.next)
        _ = burst.enqueue(.previous)
        burst.close()
        let next = burst.takeNext()
        let acceptedAfterClose = burst.enqueue(.next)
        #expect(burst.pendingCount == 0)
        #expect(next == nil)
        #expect(!acceptedAfterClose)
    }

    @Test func newWindowBurstDoesNotInheritPreviousRequests() {
        var burst = WindowMoveBurst()
        burst.begin()
        _ = burst.enqueue(.next)
        burst.close()
        burst.begin()
        #expect(burst.pendingCount == 0)
        #expect(burst.accepting)
        let accepted = burst.enqueue(.previous)
        let next = burst.takeNext()
        let remaining = burst.takeNext()
        #expect(accepted)
        #expect(next == .previous)
        #expect(remaining == nil)
    }
}
