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

    @Test(arguments: [1, 2, 4, 5])
    func numberedJumpUsesIndicatorNumberingAcrossDisplays(number: Int) async throws {
        let backend = SwitchBackend()
        let route = try await SpaceSwitch(backend: backend).jumpToDesktop(number)
        let expectedID: UInt64 = [1: 20, 2: 21, 4: 12, 5: 13][number]!
        let expectedDisplay = number < 3 ? "other" : "active"
        #expect(route.destinationID == expectedID)
        #expect(route.displayID == expectedDisplay)
        #expect(
            CurrentSpace(displays: backend.displays(), activeDisplayID: expectedDisplay)
                == .desktop(number)
        )
        #expect(
            backend.activations
                == (number == 1 ? [] : [.init(space: expectedID, display: expectedDisplay)])
        )
        #expect(backend.currentSpace == (number < 3 ? 11 : expectedID))
        #expect(backend.otherCurrentSpace == (number < 3 ? expectedID : 20))
        #expect(backend.windowCalls == 0)
    }

    @Test func numberedJumpSkipsFullscreenWithoutVisitingIntermediateSpaces() async throws {
        let backend = SwitchBackend()
        backend.fullscreenID = 12
        let route = try await SpaceSwitch(backend: backend).jumpToDesktop(4)
        #expect(route.sourceID == 11)
        #expect(route.destinationID == 13)
        #expect(backend.activations == [.init(space: 13, display: "active")])
        #expect(
            CurrentSpace(displays: backend.displays(), activeDisplayID: "active") == .desktop(4)
        )
        #expect(backend.windowCalls == 0)
    }

    @Test func numberedJumpResolvesTheCurrentOrderOnEveryPress() async throws {
        let backend = SwitchBackend()
        let switcher = SpaceSwitch(backend: backend)
        try await switcher.jumpToDesktop(5)
        backend.spaceIDs = [13, 11, 12]
        let route = try await switcher.jumpToDesktop(5)
        #expect(route.sourceID == 13)
        #expect(route.destinationID == 12)
        #expect(backend.activations.map(\.space) == [13, 12])
        #expect(
            CurrentSpace(displays: backend.displays(), activeDisplayID: "active") == .desktop(5)
        )
        #expect(backend.windowCalls == 0)
    }

    @Test func numberedJumpToCurrentDesktopIsAnIdempotentNoOp() async throws {
        let backend = SwitchBackend()
        let switcher = SpaceSwitch(backend: backend)
        for _ in 0..<2 {
            let route = try await switcher.jumpToDesktop(3)
            #expect(route.sourceID == 11)
            #expect(route.destinationID == 11)
        }
        #expect(backend.activations.isEmpty)
        #expect(backend.currentSpace == 11)
        #expect(backend.windowCalls == 0)
    }

    @Test(arguments: [-1, 0, 6, 9])
    func missingNumberedDesktopDoesNotSwitchOrCreateAnything(number: Int) async {
        let backend = SwitchBackend()
        await #expect(throws: SpaceMoveError.desktopNotFound(number)) {
            try await SpaceSwitch(backend: backend).jumpToDesktop(number)
        }
        #expect(backend.activations.isEmpty)
        #expect(backend.currentSpace == 11)
        #expect(backend.windowCalls == 0)
    }

    @Test func numberedJumpRejectsFullscreenSource() async {
        let backend = SwitchBackend()
        backend.fullscreenID = 11
        await #expect(throws: SpaceMoveError.unsupportedSpace) {
            try await SpaceSwitch(backend: backend).jumpToDesktop(4)
        }
        #expect(backend.activations.isEmpty)
        #expect(backend.currentSpace == 11)
    }

    @Test func numberedJumpConfirmsExclusiveVisibility() async throws {
        let backend = SwitchBackend()
        backend.applyActivation = false
        var polls = 0
        let switcher = SpaceSwitch(backend: backend) {
            polls += 1
            backend.currentSpace = 13
            backend.visible = polls == 1 ? [11, 13, 20] : [13, 20]
        }
        let route = try await switcher.jumpToDesktop(5)
        #expect(route.destinationID == 13)
        #expect(polls == 2)
        #expect(backend.activations == [.init(space: 13, display: "active")])
        #expect(backend.windowCalls == 0)
    }

    @Test func numberedJumpReportsSilentFailureWithoutRetrying() async {
        let backend = SwitchBackend()
        backend.applyActivation = false
        await #expect(throws: SpaceMoveError.switchNotConfirmed(13)) {
            try await SpaceSwitch(backend: backend).jumpToDesktop(5)
        }
        #expect(backend.activations == [.init(space: 13, display: "active")])
        #expect(backend.currentSpace == 11)
        #expect(backend.windowCalls == 0)
    }

    @Test func cancelledNumberedJumpDoesNotDispatch() async {
        let backend = SwitchBackend()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SpaceSwitch(backend: backend).jumpToDesktop(5)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(backend.activations.isEmpty)
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
    var spaceIDs: [UInt64] = [11, 12, 13]
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
                spaces: spaceIDs.map { Space(id: $0, type: $0 == fullscreenID ? 4 : 0) }
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
