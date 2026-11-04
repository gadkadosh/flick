import Foundation
import Testing

@testable import Flick

@MainActor
struct WindowSwitchFocusTests {
    @Test(arguments: ["validate", "prepare", "raise"])
    func slowAXDoesNotBlockCancellationOrContinueActivation(step: String) async throws {
        let probe = FocusProbe(blocking: step)
        var activations = 0
        var confirmations = 0
        let task = Task {
            try await WindowSwitchInventory.focus(
                checkAvailability: {},
                validate: { try probe.perform("validate") },
                prepare: { try probe.perform("prepare") },
                activate: { activations += 1 },
                raise: { try probe.perform("raise") },
                isFocused: {
                    confirmations += 1
                    return true
                }
            )
        }
        defer {
            probe.release()
            task.cancel()
        }
        for _ in 0..<1000 {
            if probe.entered { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        // The test can advance on the main actor while the simulated AX request is blocked.
        #expect(probe.entered)
        #expect(!probe.finished)
        #expect(!probe.blockedOnMain)
        task.cancel()
        probe.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(activations == (step == "raise" ? 1 : 0))
        #expect(confirmations == 0)
        #expect(probe.events.last == step)
    }

    @Test func successfulActivationUsesTheExactWindowBeforeAndAfterAppActivation() async throws {
        let probe = FocusProbe()
        try await WindowSwitchInventory.focus(
            checkAvailability: {},
            validate: { try probe.perform("validate") },
            prepare: { try probe.perform("prepare") },
            activate: { try probe.perform("activate") },
            raise: { try probe.perform("raise") },
            isFocused: {
                try probe.perform("confirm")
                return true
            }
        )
        #expect(probe.events == ["validate", "prepare", "activate", "raise", "confirm"])
        #expect(probe.mainActorEvents == ["activate", "confirm"])
    }

    @Test func changedAvailabilityAfterAXReadPreventsAnyFocusRequest() async {
        let probe = FocusProbe()
        do {
            try await WindowSwitchInventory.focus(
                checkAvailability: {
                    if probe.events.contains("validate") {
                        throw FlickError.message("The Space changed.")
                    }
                },
                validate: { try probe.perform("validate") },
                prepare: { try probe.perform("prepare") },
                activate: { try probe.perform("activate") },
                raise: { try probe.perform("raise") },
                isFocused: { true }
            )
            Issue.record("Activation should reject the changed Space.")
        } catch {
            #expect(error.localizedDescription == "The Space changed.")
        }
        #expect(probe.events == ["validate"])
    }
}

private final class FocusProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let blocking: String?
    private var recorded: [String] = []
    private var onMain: [String] = []
    private var didEnter = false
    private var didFinish = false
    private var blockedMain = false

    init(blocking: String? = nil) { self.blocking = blocking }

    var entered: Bool { lock.withLock { didEnter } }
    var finished: Bool { lock.withLock { didFinish } }
    var blockedOnMain: Bool { lock.withLock { blockedMain } }
    var events: [String] { lock.withLock { recorded } }
    var mainActorEvents: [String] { lock.withLock { onMain } }

    func perform(_ event: String) throws {
        lock.withLock {
            recorded.append(event)
            if Thread.isMainThread { onMain.append(event) }
            if event == blocking {
                didEnter = true
                blockedMain = Thread.isMainThread
            }
        }
        guard event == blocking else { return }
        let result = gate.wait(timeout: .now() + 2)
        lock.withLock { didFinish = true }
        if result == .timedOut {
            throw FlickError.message("The main actor could not cancel a blocked AX request.")
        }
    }

    func release() { gate.signal() }
}
