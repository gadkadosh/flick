import AppKit
import FlickCore
import Testing

@testable import Flick

@MainActor
struct CurrentSpaceIndicatorTests {
    @Test func launchAndNotificationsUpdateTheActualButtonImage() throws {
        let button = NSButton()
        let notifications = NotificationCenter()
        var space = CurrentSpace.desktop(2)
        let indicator = CurrentSpaceIndicator(button: button, notifications: notifications) {
            space
        }
        indicator.start()
        defer { indicator.stop() }

        let initial = try #require(button.image)
        #expect(initial.isTemplate)
        #expect(initial.accessibilityDescription == "Flick — Desktop 2")
        #expect(button.accessibilityLabel() == "Flick — Desktop 2")
        let initialPixels = try #require(initial.tiffRepresentation)

        space = .desktop(3)
        notifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        #expect(button.image?.accessibilityDescription == "Flick — Desktop 3")
        #expect(try #require(button.image?.tiffRepresentation) != initialPixels)

        space = .fullscreen
        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(button.image?.accessibilityDescription == "Flick — Fullscreen or Split View Space")
        #expect(button.image?.tiffRepresentation != initialPixels)
    }

    @Test func failedReadReplacesTheOldNumberAndRecoversOnWake() throws {
        enum ReadError: Error { case unavailable }
        let button = NSButton()
        let notifications = NotificationCenter()
        var failing = false
        let indicator = CurrentSpaceIndicator(button: button, notifications: notifications) {
            if failing { throw ReadError.unavailable }
            return .desktop(8)
        }
        indicator.start()
        defer { indicator.stop() }
        let numberPixels = try #require(button.image?.tiffRepresentation)

        failing = true
        notifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        #expect(button.accessibilityLabel() == "Flick — Current Space unavailable")
        #expect(try #require(button.image?.tiffRepresentation) != numberPixels)

        failing = false
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(button.accessibilityLabel() == "Flick — Desktop 8")
        #expect(button.image?.tiffRepresentation == numberPixels)
    }

    @Test func multipleDigitsFitInsteadOfClipping() throws {
        let button = NSButton()
        var space = CurrentSpace.desktop(1)
        let indicator = CurrentSpaceIndicator(button: button, notifications: NotificationCenter()) {
            space
        }
        indicator.refresh()
        let singleWidth = try #require(button.image).size.width
        space = .desktop(123)
        indicator.refresh()
        #expect(try #require(button.image).size.width > singleWidth)
        #expect(button.accessibilityLabel() == "Flick — Desktop 123")
    }

    @Test func pollingCatchesUnannouncedChangesAndStopRemovesObservers() async throws {
        let button = NSButton()
        let notifications = NotificationCenter()
        var space = CurrentSpace.desktop(1)
        let indicator = CurrentSpaceIndicator(button: button, notifications: notifications) {
            space
        }
        indicator.start(pollInterval: 0.01)
        defer { indicator.stop() }
        // Starting twice must not leave duplicate timers or observers behind.
        indicator.start(pollInterval: 0.01)
        space = .desktop(4)
        for _ in 0..<100 where button.accessibilityLabel() != "Flick — Desktop 4" {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(button.accessibilityLabel() == "Flick — Desktop 4")

        indicator.stop()
        space = .desktop(5)
        notifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(button.accessibilityLabel() == "Flick — Desktop 4")
    }
}
