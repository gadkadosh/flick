import AppKit
import FlickCore
import Testing
@testable import Flick

@MainActor
struct WindowMoverTests {
    @Test func inputDuringConfirmationDiscardsQueueBeforeRefocusingEvenIfFocusReturns() async {
        let harness = MoveHarness()
        harness.onStep = {
            guard harness.events.count == 1 else { return }
            #expect(harness.mover.enqueue(.previous))
            harness.focused = false
            harness.send(.keyDown, code: 48, flags: .maskCommand) // Command-Tab.
            harness.focused = true // Returning focus must not erase the interruption.
            #expect(!harness.mover.enqueue(.next))
            await Task.yield()
        }
        await #expect(throws: FlickError.self) { try await harness.run() }
        #expect(harness.events == [.move(.next)])
        #expect(harness.mover.pendingMoves == 0)
        #expect(!harness.mover.busy)
        #expect(harness.observationsStopped == 1)
    }

    @Test func clickDuringConfirmationDoesNotStealFocusBack() async {
        let harness = MoveHarness()
        harness.onStep = {
            guard harness.events.count == 1 else { return }
            #expect(harness.mover.enqueue(.previous))
            harness.focused = false
            harness.send(.leftMouseDown)
            await Task.yield()
        }
        await #expect(throws: FlickError.self) { try await harness.run() }
        #expect(harness.events == [.move(.next)])
        #expect(!harness.focused)
        #expect(harness.observationsStopped == 1)
    }

    @Test func normalTransitionFocusChangesAndMoveShortcutsKeepQueueWorking() async throws {
        let harness = MoveHarness()
        harness.onStep = {
            if harness.events.count == 1 {
                harness.send(.keyDown, code: 33, flags: [.maskAlternate, .maskShift, .maskAlphaShift])
                harness.send(.flagsChanged)
                harness.send(.mouseMoved)
                #expect(harness.mover.enqueue(.previous))
            }
            harness.focused = false // macOS can change focus during a normal transition.
            await Task.yield()
        }
        let result = try await harness.run()
        #expect(result.contains("2 Space(s)"))
        #expect(harness.events == [.move(.next), .refocus, .move(.previous), .refocus])
        #expect(harness.focused)
        #expect(harness.observationsStopped == 1)
    }

    @Test func failedStepCleansUpObservationAndDoesNotReplayOldRequests() async throws {
        let harness = MoveHarness()
        harness.onStep = {
            #expect(harness.mover.enqueue(.previous))
            throw FlickError.message("Move failed.")
        }
        await #expect(throws: FlickError.self) { try await harness.run() }
        #expect(harness.observationsStopped == 1)
        #expect(harness.mover.pendingMoves == 0)
        harness.onStep = nil
        _ = try await harness.run()
        #expect(harness.events == [.move(.next), .move(.next), .refocus])
        #expect(harness.observationsStopped == 2)
    }

    @Test func quittingFinishesOneStepAndStopsObservingBeforeAnotherCanRun() async {
        let harness = MoveHarness()
        harness.onStep = {
            #expect(harness.mover.enqueue(.previous))
            withUnsafeCurrentTask { $0?.cancel() }
            await Task.yield()
        }
        let task = Task { @MainActor in try await harness.run() }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(harness.events == [.move(.next), .refocus])
        #expect(harness.mover.pendingMoves == 0)
        #expect(!harness.mover.busy)
        #expect(harness.observationsStopped == 1)
    }

    @Test func secureInputAtStartupFailsBeforeInstallingTapOrMoving() async {
        let harness = MoveHarness()
        harness.secureInput = true
        await #expect(throws: FlickError.self) { try await harness.run() }
        #expect(harness.observationsStarted == 0)
        #expect(harness.events.isEmpty)
        #expect(!harness.mover.busy)
        #expect(!harness.mover.enqueue(.previous))
    }

    @Test func secureInputEnabledDuringSetupIsCheckedBeforeDispatch() async {
        let harness = MoveHarness()
        harness.onObservation = { harness.secureInput = true }
        await #expect(throws: FlickError.self) { try await harness.run() }
        #expect(harness.events.isEmpty)
        #expect(harness.observationsStopped == 1)
        #expect(!harness.mover.busy)
    }

    @Test func secureInputIsCheckedBeforeRefocusingEvenWithoutATimerTick() async {
        let harness = MoveHarness()
        harness.onStep = {
            #expect(harness.mover.enqueue(.previous))
            harness.secureInput = true
        }
        await #expect(throws: FlickError.self) { try await harness.run() }
        #expect(harness.events == [.move(.next)])
        #expect(harness.mover.pendingMoves == 0)
        #expect(harness.observationsStopped == 1)
    }

    @Test func secureInputDuringConfirmationStaysLatchedAfterSecureEntryEnds() async {
        let harness = MoveHarness()
        harness.onStep = {
            guard harness.events.count == 1 else { return }
            #expect(harness.mover.enqueue(.previous))
            harness.secureInput = true
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while harness.interruptions == 0 && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(2))
            }
            #expect(harness.interruptions == 1) // The real watcher must notice during the await.
            harness.secureInput = false
            #expect(!harness.mover.enqueue(.previous))
        }
        await #expect(throws: FlickError.self) { try await harness.run() }
        #expect(harness.events == [.move(.next)])
        #expect(harness.mover.pendingMoves == 0)
        #expect(harness.observationsStopped == 1)
        #expect(!harness.mover.busy)
    }

    @Test func missingInputObservationFailsBeforeDispatchAndReleasesBusyState() async {
        let mover = WindowMover(
            capture: { .init(windowID: 77, isFocused: { true }, refocus: { Issue.record("Must not refocus") }) },
            moveStep: { _, _ in Issue.record("Must not move without input observation") },
            observeInput: { _, _ in throw FlickError.message("Observation unavailable.") }
        )
        await #expect(throws: FlickError.self) { try await mover.move(.next, preset: .optionShift) }
        #expect(!mover.busy)
        #expect(!mover.enqueue(.previous))
    }
}

@MainActor
private final class MoveHarness {
    enum Event: Equatable { case move(Direction), refocus }
    var mover: WindowMover!
    var events: [Event] = []
    var focused = true
    var onStep: (() async throws -> Void)?
    var observationsStarted = 0
    var observationsStopped = 0
    var secureInput = false
    var interruptions = 0
    var onObservation: (() -> Void)?
    private var observation: WindowMoveInputMonitor?

    init() {
        mover = WindowMover(
            capture: { [unowned self] in
                .init(windowID: 77, isFocused: { self.focused }, refocus: {
                    self.events.append(.refocus)
                    self.focused = true
                })
            },
            moveStep: { [unowned self] windowID, direction in
                #expect(windowID == 77)
                self.events.append(.move(direction))
                try await self.onStep?()
            },
            observeInput: { [unowned self] shortcuts, interrupt in
                let observation = try WindowMoveInputMonitor(
                    shortcuts: shortcuts,
                    interrupt: { [unowned self] in
                        self.interruptions += 1
                        interrupt()
                    },
                    isSecureInputEnabled: { [unowned self] in self.secureInput },
                    startTap: { [unowned self] _ in
                        self.observationsStarted += 1
                        return { [unowned self] in self.observationsStopped += 1 }
                    }
                )
                self.observation = observation
                self.onObservation?()
                return observation
            }
        )
    }

    func send(_ type: CGEventType, code: Int64 = 0, flags: CGEventFlags = []) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
        event.flags = flags
        observation?.receive(type: type, event: event)
    }

    func run() async throws -> String { try await mover.move(.next, preset: .optionShift) }
}
