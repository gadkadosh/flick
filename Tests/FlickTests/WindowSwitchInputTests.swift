import AppKit
import FlickCore
import Testing

@testable import Flick

@MainActor
struct WindowSwitchInputTests {
    @Test func actualEventAdapterDrivesSelectionAndReleaseWithoutInstallingATap() async throws {
        let first = WindowIdentity(processID: 10, windowID: 1)
        let second = WindowIdentity(processID: 10, windowID: 2)
        var focused: [WindowIdentity] = []
        let switcher = WindowSwitcher(
            capture: {
                WindowSwitchSnapshot(
                    targets: [first, second].map { id in
                        WindowSwitchTarget(id: id, title: "Window", appName: "App", icon: nil) {
                            focused.append(id)
                        }
                    },
                    focused: first,
                    screenFrame: .zero
                )
            },
            present: { _, _ in },
            dismiss: {},
            canBegin: { true },
            report: { _ in }
        )
        let input = WindowSwitchInput(isSecureInputEnabled: { false })
        input.onCommand = { switcher.receive($0) }
        input.isBusy = { switcher.busy }
        #expect(
            input.receive(type: .keyDown, event: key(48, flags: [.maskAlternate, .maskAlphaShift]))
        )
        #expect(!input.receive(type: .flagsChanged, event: key(58)))
        #expect(input.receive(type: .keyUp, event: key(48)))
        for _ in 0..<1000 {
            if !focused.isEmpty { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(focused == [second])
        #expect(!switcher.busy)
    }

    @Test func typingAfterQuickReleaseCancelsEvenBeforeQueuedCommandsAreDelivered() async {
        let input = WindowSwitchInput(isSecureInputEnabled: { false })
        var commands: [WindowSwitchKeys.Command] = []
        input.onCommand = { commands.append($0) }
        #expect(input.receive(type: .keyDown, event: key(48, flags: .maskAlternate)))
        #expect(!input.receive(type: .flagsChanged, event: key(58)))
        #expect(!input.receive(type: .keyDown, event: key(0)))
        await flushCommands()
        #expect(commands == [.begin(backwards: false), .commit, .cancel])
    }

    @Test func clicksAndSecureInputCancelAPendingCommit() async {
        var secure = false
        let input = WindowSwitchInput(isSecureInputEnabled: { secure })
        input.isBusy = { true }
        var commands: [WindowSwitchKeys.Command] = []
        input.onCommand = { commands.append($0) }
        #expect(!input.receive(type: .leftMouseDown, event: key(0)))
        await flushCommands()
        secure = true
        #expect(!input.receive(type: .flagsChanged, event: key(58)))
        await flushCommands()
        #expect(commands == [.cancel, .cancel])
    }

    @Test func secureInputInvalidatesAnUndeliveredBeginAndCommit() async {
        var secure = false
        let input = WindowSwitchInput(isSecureInputEnabled: { secure })
        var commands: [WindowSwitchKeys.Command] = []
        input.onCommand = { commands.append($0) }
        _ = input.receive(type: .keyDown, event: key(48, flags: .maskAlternate))
        _ = input.receive(type: .flagsChanged, event: key(58))
        secure = true
        _ = input.receive(type: .flagsChanged, event: key(58))
        await flushCommands()
        #expect(commands == [.cancel])
    }

    @Test func losingKeyboardCaptureCancelsAndDoesNotCommitOnOptionRelease() async {
        let input = WindowSwitchInput(isSecureInputEnabled: { false })
        var commands: [WindowSwitchKeys.Command] = []
        var failures: [String] = []
        input.onCommand = { commands.append($0) }
        input.onFailure = { failures.append($0) }
        _ = input.receive(type: .keyDown, event: key(48, flags: .maskAlternate))
        #expect(!input.receive(type: .tapDisabledByTimeout, event: key(48)))
        _ = input.receive(type: .flagsChanged, event: key(58))
        await flushCommands()
        #expect(commands == [.begin(backwards: false), .cancel])
        #expect(
            failures == ["Window switching was cancelled because keyboard capture was interrupted."]
        )
    }

    @Test func stoppingDiscardsCommandsAlreadyQueuedByTheTap() async {
        let input = WindowSwitchInput(isSecureInputEnabled: { false })
        var commands: [WindowSwitchKeys.Command] = []
        input.onCommand = { commands.append($0) }
        _ = input.receive(type: .keyDown, event: key(48, flags: .maskAlternate))
        input.stop()
        input.stop()
        await flushCommands()
        #expect(commands == [.cancel, .cancel])
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.flags = flags
        return event
    }

    private func flushCommands() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
