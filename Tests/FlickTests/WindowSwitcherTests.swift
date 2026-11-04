import AppKit
import FlickCore
import Testing

@testable import Flick

@MainActor
struct WindowSwitcherTests {
    @Test func quickReleaseAndExtraTabWhileDiscoveryIsPendingSelectTheRightWindow() async throws {
        let harness = SwitchHarness()
        var gate: CheckedContinuation<Void, Never>?
        harness.beforeCapture = { await withCheckedContinuation { gate = $0 } }
        harness.switcher.receive(.begin(backwards: false))
        try await eventually { gate != nil }
        harness.switcher.receive(.advance(backwards: false))
        harness.switcher.receive(.commit)
        #expect(harness.focusedTargets.isEmpty)
        gate?.resume()
        try await eventually { !harness.switcher.busy }
        #expect(harness.focusedTargets == [harness.ids[2]])
        #expect(harness.selections == [harness.ids[1], harness.ids[2]])
        #expect(harness.captureCount == 1)
        #expect(harness.dismissals == 1)
        #expect(harness.messages.last == "Switched to App — Window 3.")
    }

    @Test func cancellingPendingDiscoveryNeverShowsOrFocusesItsLateResult() async throws {
        let harness = SwitchHarness()
        var gate: CheckedContinuation<Void, Never>?
        harness.beforeCapture = { await withCheckedContinuation { gate = $0 } }
        harness.switcher.receive(.begin(backwards: false))
        try await eventually { gate != nil }
        harness.switcher.receive(.commit)
        harness.switcher.receive(.cancel)
        gate?.resume()
        for _ in 0..<20 { await Task.yield() }
        #expect(!harness.switcher.busy)
        #expect(harness.selections.isEmpty)
        #expect(harness.focusedTargets.isEmpty)
        #expect(harness.messages.isEmpty)
    }

    @Test func cancelledDiscoveryCannotOverwriteANewerSession() async throws {
        let harness = SwitchHarness()
        var gate: CheckedContinuation<Void, Never>?
        harness.beforeCapture = {
            if harness.captureCount == 1 {
                await withCheckedContinuation { gate = $0 }
            }
        }
        harness.switcher.receive(.begin(backwards: false))
        try await eventually { gate != nil }
        harness.switcher.receive(.cancel)
        harness.switcher.receive(.begin(backwards: true))
        try await eventually { !harness.selections.isEmpty }
        gate?.resume()
        for _ in 0..<20 { await Task.yield() }
        harness.switcher.receive(.commit)
        try await eventually { !harness.switcher.busy }
        #expect(harness.focusedTargets == [harness.ids[2]])
        #expect(harness.selections == [harness.ids[2]])
        #expect(harness.captureCount == 2)
    }

    @Test func quickTapsToggleBetweenTwoRecentWindowsAndOverlayUsesTheSameOrder() async throws {
        let harness = SwitchHarness()
        for _ in 0..<3 {
            harness.switcher.receive(.begin(backwards: false))
            harness.switcher.receive(.commit)
            try await eventually { !harness.switcher.busy }
        }
        #expect(harness.focusedTargets == [harness.ids[1], harness.ids[0], harness.ids[1]])
        #expect(harness.presentedOrders[1] == [harness.ids[1], harness.ids[0], harness.ids[2]])
    }

    @Test func reverseThenEscapeLeavesFocusUnchanged() async throws {
        let harness = SwitchHarness()
        harness.switcher.receive(.begin(backwards: true))
        try await eventually { !harness.selections.isEmpty }
        #expect(harness.selections == [harness.ids[2]])
        harness.switcher.receive(.cancel)
        harness.switcher.receive(.commit)
        #expect(harness.focusedTargets.isEmpty)
        #expect(!harness.switcher.busy)
        #expect(harness.dismissals == 1)
    }

    @Test func anotherOperationBlocksDiscoveryAndSelection() {
        let harness = SwitchHarness()
        harness.allowed = false
        harness.switcher.receive(.begin(backwards: false))
        harness.switcher.receive(.commit)
        #expect(harness.captureCount == 0)
        #expect(harness.focusedTargets.isEmpty)
        #expect(harness.messages == ["Wait for the current operation before switching windows."])
        #expect(!harness.switcher.busy)
    }

    @Test func vanishedWindowReportsFailureRatherThanClaimingSuccess() async throws {
        let harness = SwitchHarness()
        harness.failFocus = true
        harness.switcher.receive(.begin(backwards: false))
        harness.switcher.receive(.commit)
        try await eventually { !harness.switcher.busy }
        #expect(harness.focusedTargets.isEmpty)
        #expect(harness.messages == ["Window disappeared."])
        #expect(harness.dismissals == 1)
    }

    @Test func emptyInventoryDoesNotActivateAnything() async throws {
        let harness = SwitchHarness()
        harness.empty = true
        harness.switcher.receive(.begin(backwards: false))
        harness.switcher.receive(.commit)
        try await eventually { !harness.switcher.busy }
        #expect(harness.focusedTargets.isEmpty)
        #expect(harness.selections.isEmpty)
        #expect(harness.messages == ["No eligible windows on this display’s visible Space."])
    }

    @Test func tapsQueuedDuringDiscoveryAreCommittedInOrder() async throws {
        let harness = SwitchHarness()
        harness.switcher.receive(.begin(backwards: false))
        harness.switcher.receive(.commit)
        harness.switcher.receive(.begin(backwards: false))
        harness.switcher.receive(.commit)
        try await eventually { !harness.switcher.busy }
        #expect(harness.focusedTargets == [harness.ids[1], harness.ids[0]])
        #expect(harness.captureCount == 2)
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw FlickError.message("Timed out waiting for the switcher.")
    }
}

@MainActor
private final class SwitchHarness {
    let ids = (1...3).map { WindowIdentity(processID: 42, windowID: UInt32($0)) }
    var focused: WindowIdentity?
    var beforeCapture: (() async -> Void)?
    var allowed = true
    var failFocus = false
    var empty = false
    var captureCount = 0
    var focusedTargets: [WindowIdentity] = []
    var selections: [WindowIdentity] = []
    var presentedOrders: [[WindowIdentity]] = []
    var messages: [String] = []
    var dismissals = 0
    lazy var switcher = WindowSwitcher(
        capture: { [self] in
            captureCount += 1
            await beforeCapture?()
            return WindowSwitchSnapshot(
                targets: empty
                    ? []
                    : ids.map { id in
                        WindowSwitchTarget(
                            id: id,
                            title: "Window \(id.windowID)",
                            appName: "App",
                            icon: nil
                        ) { [self] in
                            if failFocus { throw FlickError.message("Window disappeared.") }
                            focusedTargets.append(id)
                            focused = id
                        }
                    },
                focused: focused,
                screenFrame: NSRect(x: 0, y: 0, width: 1000, height: 800)
            )
        },
        present: { [self] snapshot, selected in
            selections.append(selected)
            presentedOrders.append(snapshot.targets.map(\.id))
        },
        dismiss: { [self] in dismissals += 1 },
        canBegin: { [self] in allowed },
        report: { [self] in messages.append($0) }
    )

    init() { focused = ids[0] }
}
