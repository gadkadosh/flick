import Testing

@testable import FlickCore

@MainActor
struct SpaceMoveTests {
    @Test func followsOnlyAfterExactDestinationMembershipIsConfirmed() async throws {
        let backend = FakeSpaceBackend()
        backend.applyMove = false
        backend.applyFollow = false
        var polls = 0
        let mover = SpaceMove(backend: backend) {
            polls += 1
            if polls == 1 {
                #expect(backend.events == [.move(77, 2)])
                backend.membership = [1, 2]  // Adding to a Space alone is insufficient.
            } else if polls == 2 {
                #expect(backend.events == [.move(77, 2)])
                backend.membership = [2]
            } else {
                #expect(backend.events == [.move(77, 2), .follow(2, "display")])
                backend.currentSpace = 2
            }
        }
        let route = try await mover.move(windowID: 77, direction: .next)
        #expect(route.destinationID == 2)
        #expect(polls == 3)
        #expect(backend.membership == [2])
        #expect(backend.currentSpace == 2)
    }

    @Test func silentMoveFailureNeverSwitchesDesktops() async {
        let backend = FakeSpaceBackend()
        backend.applyMove = false
        let mover = SpaceMove(backend: backend)
        let started = ContinuousClock.now
        await #expect(throws: SpaceMoveError.moveNotConfirmed(2)) {
            try await mover.move(windowID: 77, direction: .next)
        }
        #expect(started.duration(to: .now) >= .seconds(1))
        #expect(backend.events == [.move(77, 2)])
        #expect(backend.currentSpace == 1)
    }

    @Test func silentFollowFailureIsReportedWithoutExtraNavigation() async {
        let backend = FakeSpaceBackend()
        backend.applyFollow = false
        let mover = SpaceMove(backend: backend)
        let started = ContinuousClock.now
        await #expect(throws: SpaceMoveError.followNotConfirmed(2)) {
            try await mover.move(windowID: 77, direction: .next)
        }
        #expect(started.duration(to: .now) >= .seconds(1))
        #expect(backend.events == [.move(77, 2), .follow(2, "display")])
        #expect(backend.membership == [2])
        #expect(backend.currentSpace == 1)
    }

    @Test func aBoundaryDoesNotDispatchAnyOperation() async {
        let backend = FakeSpaceBackend()
        await #expect(throws: SpaceMoveError.boundary(.previous)) {
            try await SpaceMove(backend: backend, pause: {}).move(
                windowID: 77,
                direction: .previous
            )
        }
        #expect(backend.events.isEmpty)
    }

    @Test func moveExceptionDoesNotAttemptFollowing() async {
        let backend = FakeSpaceBackend()
        backend.moveError = .rejected
        await #expect(throws: FakeSpaceBackend.Failure.rejected) {
            try await SpaceMove(backend: backend, pause: {}).move(windowID: 77, direction: .next)
        }
        #expect(backend.events == [.move(77, 2)])
        #expect(backend.membership == [1])
        #expect(backend.currentSpace == 1)
    }

    @Test func rejectedFollowReportsThatTheWindowAlreadyMoved() async {
        let backend = FakeSpaceBackend()
        backend.rejectFollow = true
        await #expect(throws: SpaceMoveError.followRejected) {
            try await SpaceMove(backend: backend).move(windowID: 77, direction: .next)
        }
        #expect(backend.membership == [2])
        #expect(backend.currentSpace == 1)
        #expect(backend.events == [.move(77, 2), .follow(2, "display")])
    }

    @Test func cancellationBeforeDispatchLeavesTheDesktopAlone() async {
        let backend = FakeSpaceBackend()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SpaceMove(backend: backend, pause: {}).move(
                windowID: 77,
                direction: .next
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(backend.events.isEmpty)
    }

    @Test func cancellationFinishesTheRequestedMoveButStopsTheNextOne() async throws {
        let backend = FakeSpaceBackend()
        backend.applyMove = false
        let mover = SpaceMove(backend: backend) {
            withUnsafeCurrentTask { $0?.cancel() }
            backend.membership = [2]
        }
        let task = Task { @MainActor in
            let route = try await mover.move(windowID: 77, direction: .next)
            await #expect(throws: CancellationError.self) {
                try await mover.move(windowID: 77, direction: .previous)
            }
            return route
        }
        let route = try await task.value
        #expect(route.destinationID == 2)
        #expect(backend.events == [.move(77, 2), .follow(2, "display")])
        #expect(backend.currentSpace == 2)
    }
}

@MainActor
private final class FakeSpaceBackend: SpaceBackend {
    enum Event: Equatable {
        case move(UInt32, UInt64)
        case follow(UInt64, String)
    }
    enum Failure: Error { case rejected }
    var events: [Event] = []
    var membership: [UInt64] = [1]
    var currentSpace: UInt64 = 1
    var applyMove = true
    var applyFollow = true
    var rejectFollow = false
    var moveError: Failure?

    func displays() -> [SpaceDisplay] {
        [
            SpaceDisplay(
                id: "display",
                currentSpaceID: currentSpace,
                spaces: [Space(id: 1), Space(id: 2), Space(id: 3)]
            )
        ]
    }

    func spaces(for windowID: UInt32) -> [UInt64] { membership }

    func move(windowID: UInt32, to spaceID: UInt64) throws {
        events.append(.move(windowID, spaceID))
        if let moveError { throw moveError }
        if applyMove { membership = [spaceID] }
    }

    func activate(spaceID: UInt64, on displayID: String) throws {
        events.append(.follow(spaceID, displayID))
        if rejectFollow { throw Failure.rejected }
        if applyFollow { currentSpace = spaceID }
    }
}
