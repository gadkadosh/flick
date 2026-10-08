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

    @Test func partialFailureDropsPendingRequestsButPreservesExactRollbackRoute() {
        var burst = WindowMoveBurst()
        burst.begin()
        burst.recordCompleted(.next)
        burst.recordCompleted(.next)
        burst.recordCompleted(.previous)
        _ = burst.enqueue(.next)
        burst.close()
        #expect(burst.pendingCount == 0)
        #expect(burst.completed == [.next, .next, .previous])
        #expect(burst.rollbackPath == [.next, .previous, .previous])
    }

    @Test func newWindowBurstDoesNotInheritPreviousRequestsOrRoute() {
        var burst = WindowMoveBurst()
        burst.begin()
        burst.recordCompleted(.next)
        _ = burst.enqueue(.next)
        burst.close()
        burst.begin()
        #expect(burst.completed.isEmpty)
        #expect(burst.rollbackPath.isEmpty)
        #expect(burst.pendingCount == 0)
        #expect(burst.accepting)
    }
}
