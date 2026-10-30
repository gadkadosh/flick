import Testing

@testable import FlickCore

@MainActor
struct SpaceSwitchTests {
    @Test func switchesOnlyTheSelectedDisplayWithoutTouchingWindows() async throws {
        let backend = SwitchBackend()
        let route = try await SpaceSwitch(backend: backend).switchSpace(
            displayID: "active",
            direction: .next
        )
        #expect(route.displayID == "active")
        #expect(route.sourceID == 11)
        #expect(route.destinationID == 12)
        #expect(backend.activations == [.init(space: 12, display: "active")])
        #expect(backend.currentSpace == 12)
        #expect(backend.otherCurrentSpace == 20)
        #expect(backend.visible == [12, 20])
        #expect(backend.windowCalls == 0)
    }

    @Test func waitsForTheDesktopRatherThanTrustingDispatch() async throws {
        let backend = SwitchBackend()
        backend.applyActivation = false
        var polls = 0
        let switcher = SpaceSwitch(backend: backend) {
            polls += 1
            #expect(backend.activations == [.init(space: 12, display: "active")])
            backend.currentSpace = 12
            backend.visible = polls == 1 ? [11, 12, 20] : [12, 20]
        }
        let route = try await switcher.switchSpace(displayID: "active", direction: .next)
        #expect(route.destinationID == 12)
        #expect(polls == 2)
        #expect(backend.visible == [12, 20])
        #expect(backend.windowCalls == 0)
    }

    @Test func rapidDirectionsUseTheNewlyConfirmedDesktop() async throws {
        let backend = SwitchBackend()
        let switcher = SpaceSwitch(backend: backend)
        try await switcher.switchSpace(displayID: "active", direction: .next)
        try await switcher.switchSpace(displayID: "active", direction: .next)
        try await switcher.switchSpace(displayID: "active", direction: .previous)
        #expect(backend.activations.map(\.space) == [12, 13, 12])
        #expect(backend.currentSpace == 12)
        #expect(backend.windowCalls == 0)
    }

    @Test func silentFailureIsReportedWithoutRetryingOrNavigatingBack() async {
        let backend = SwitchBackend()
        backend.applyActivation = false
        await #expect(throws: SpaceMoveError.switchNotConfirmed(12)) {
            try await SpaceSwitch(backend: backend).switchSpace(
                displayID: "active",
                direction: .next
            )
        }
        #expect(backend.activations == [.init(space: 12, display: "active")])
        #expect(backend.currentSpace == 11)
        #expect(backend.windowCalls == 0)
    }

    @Test(arguments: [[UInt64](), [11], [11, 12]])
    func currentIDWithoutExclusiveDestinationVisibilityIsNotSuccess(visible: [UInt64]) async {
        let backend = SwitchBackend()
        backend.applyVisibility = false
        backend.visible = visible + [20]
        await #expect(throws: SpaceMoveError.switchNotConfirmed(12)) {
            try await SpaceSwitch(backend: backend).switchSpace(
                displayID: "active",
                direction: .next
            )
        }
        #expect(backend.currentSpace == 12)
        #expect(backend.visible == visible + [20])
        #expect(backend.activations == [.init(space: 12, display: "active")])
        #expect(backend.windowCalls == 0)
    }

    @Test func missingDisplayDoesNotGuessOrSwitchAnotherDisplay() async {
        let backend = SwitchBackend()
        await #expect(throws: SpaceMoveError.invalidLayout) {
            try await SpaceSwitch(backend: backend).switchSpace(
                displayID: "missing",
                direction: .next
            )
        }
        #expect(backend.activations.isEmpty)
        #expect(backend.currentSpace == 11)
    }

    @Test func boundaryDoesNotWrap() async {
        let backend = SwitchBackend()
        await #expect(throws: SpaceMoveError.boundary(.previous)) {
            try await SpaceSwitch(backend: backend).switchSpace(
                displayID: "active",
                direction: .previous
            )
        }
        #expect(backend.activations.isEmpty)
        #expect(backend.currentSpace == 11)
    }

    @Test(arguments: [11, 12]) func fullscreenSourceOrDestinationIsRejected(fullscreenID: UInt64)
        async
    {
        let backend = SwitchBackend()
        backend.fullscreenID = fullscreenID
        await #expect(throws: SpaceMoveError.unsupportedSpace) {
            try await SpaceSwitch(backend: backend).switchSpace(
                displayID: "active",
                direction: .next
            )
        }
        #expect(backend.activations.isEmpty)
        #expect(backend.currentSpace == 11)
    }

    @Test func rejectedActivationIsNotRetried() async {
        let backend = SwitchBackend()
        backend.rejectActivation = true
        await #expect(throws: SwitchBackend.Failure.rejected) {
            try await SpaceSwitch(backend: backend).switchSpace(
                displayID: "active",
                direction: .next
            )
        }
        #expect(backend.activations.count == 1)
        #expect(backend.currentSpace == 11)
    }

    @Test func cancellationBeforeDispatchLeavesDesktopsAlone() async {
        let backend = SwitchBackend()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SpaceSwitch(backend: backend).switchSpace(
                displayID: "active",
                direction: .next
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(backend.activations.isEmpty)
        #expect(backend.currentSpace == 11)
    }

    @Test func cancellationConfirmsDispatchedSwitchButStopsTheNextStep() async throws {
        let backend = SwitchBackend()
        backend.applyActivation = false
        let switcher = SpaceSwitch(backend: backend) {
            withUnsafeCurrentTask { $0?.cancel() }
            backend.currentSpace = 12
            backend.visible = [12, 20]
        }
        let task = Task { @MainActor in
            let route = try await switcher.switchSpace(displayID: "active", direction: .next)
            await #expect(throws: CancellationError.self) {
                try await switcher.switchSpace(displayID: "active", direction: .next)
            }
            return route
        }
        let route = try await task.value
        #expect(route.destinationID == 12)
        #expect(backend.activations == [.init(space: 12, display: "active")])
        #expect(backend.currentSpace == 12)
    }
}

@MainActor
private final class SwitchBackend: SpaceBackend {
    struct Activation: Equatable {
        let space: UInt64
        let display: String
    }
    enum Failure: Error { case rejected, unexpectedWindowAccess }
    var activations: [Activation] = []
    var currentSpace: UInt64 = 11
    var otherCurrentSpace: UInt64 = 20
    var visible: [UInt64] = [11, 20]
    var applyVisibility = true
    var fullscreenID: UInt64?
    var applyActivation = true
    var rejectActivation = false
    var windowCalls = 0

    func displays() -> [SpaceDisplay] {
        [
            SpaceDisplay(
                id: "other",
                currentSpaceID: otherCurrentSpace,
                spaces: [Space(id: 20), Space(id: 21)]
            ),
            SpaceDisplay(
                id: "active",
                currentSpaceID: currentSpace,
                spaces: [11, 12, 13].map { Space(id: $0, type: $0 == fullscreenID ? 4 : 0) }
            ),
        ]
    }

    func visibleSpaces() -> [UInt64] { visible }

    func activate(spaceID: UInt64, on displayID: String) throws {
        activations.append(Activation(space: spaceID, display: displayID))
        if rejectActivation { throw Failure.rejected }
        if applyActivation {
            if displayID == "active" {
                currentSpace = spaceID
                if applyVisibility { visible = [spaceID, otherCurrentSpace] }
            } else {
                otherCurrentSpace = spaceID
                if applyVisibility { visible = [currentSpace, spaceID] }
            }
        }
    }

    func spaces(for windowID: UInt32) throws -> [UInt64] {
        windowCalls += 1
        throw Failure.unexpectedWindowAccess
    }

    func move(windowID: UInt32, to spaceID: UInt64) throws {
        windowCalls += 1
        throw Failure.unexpectedWindowAccess
    }
}
