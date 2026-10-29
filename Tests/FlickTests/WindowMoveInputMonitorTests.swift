import AppKit
import FlickCore
import Testing

@testable import Flick

@MainActor
struct WindowMoveInputMonitorTests {
    @Test func onlyConfiguredMoveKeysAreAllowedWithModifiersHeld() {
        for preset in MoveShortcutPreset.allCases {
            let shortcuts = Direction.allCases.map { preset.shortcut(for: $0) }
            for shortcut in shortcuts {
                let event = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: shortcut.keyCode,
                    keyDown: true
                )!
                event.flags = CGEventFlags(rawValue: shortcut.flags).union([
                    .maskAlphaShift, .maskSecondaryFn,
                ])
                #expect(
                    !WindowMoveInputMonitor.interrupts(
                        type: .keyDown,
                        event: event,
                        shortcuts: shortcuts
                    )
                )
                event.flags.insert(.maskCommand)
                #expect(
                    WindowMoveInputMonitor.interrupts(
                        type: .keyDown,
                        event: event,
                        shortcuts: shortcuts
                    )
                )
            }
            let typing = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            #expect(
                WindowMoveInputMonitor.interrupts(
                    type: .keyDown,
                    event: typing,
                    shortcuts: shortcuts
                )
            )
        }
    }

    @Test func stoppingCancelsTheSecurityWatcherAndIsIdempotent() async throws {
        var secureInput = false
        var interruptions = 0
        var stops = 0
        let monitor = try WindowMoveInputMonitor(
            shortcuts: [],
            interrupt: { interruptions += 1 },
            isSecureInputEnabled: { secureInput },
            startTap: { _ in { stops += 1 } }
        )
        monitor.stop()
        monitor.stop()
        secureInput = true
        try await Task.sleep(for: .milliseconds(30))
        #expect(stops == 1)
        #expect(interruptions == 0)
    }

    @Test func losingTheTapStopsTheQueueRatherThanSilentlyLosingProtection() {
        let event = CGEvent(source: nil)!
        for type: CGEventType in [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .tapDisabledByTimeout,
            .tapDisabledByUserInput,
        ] {
            #expect(WindowMoveInputMonitor.interrupts(type: type, event: event, shortcuts: []))
        }
        for type: CGEventType in [.mouseMoved, .flagsChanged, .keyUp] {
            #expect(!WindowMoveInputMonitor.interrupts(type: type, event: event, shortcuts: []))
        }
    }
}
