import AppKit
import FlickCore
import SkyLightBridge

@MainActor
final class SpaceSwitcher {
    private(set) var busy = false
    private var burst = DirectionBurst()
    var pendingSwitches: Int { burst.pendingCount }

    func enqueue(_ direction: Direction) -> Bool {
        guard busy else { return false }
        return burst.enqueue(direction)
    }

    func jumpToDesktop(_ number: Int) async throws -> String {
        guard !busy else { throw FlickError.message("A desktop switch is already in progress.") }
        busy = true
        defer { busy = false }
        try checkSwitchingAvailable()
        try await SpaceSwitch(backend: SkyLight()).jumpToDesktop(number)
        return "Desktop \(number) visible; destination confirmed. No windows moved."
    }

    private func checkSwitchingAvailable() throws {
        guard FlickSkyLightAvailable() else {
            throw FlickError.message("Direct Space switching is unavailable on this macOS version.")
        }
        guard NSEvent.pressedMouseButtons == 0 else {
            throw FlickError.message("Release the mouse buttons before switching Spaces.")
        }
    }

    func switchSpace(_ direction: Direction) async throws -> String {
        guard !busy else { throw FlickError.message("A desktop switch is already in progress.") }
        busy = true
        defer {
            burst.close()
            busy = false
        }
        try checkSwitchingAvailable()
        let backend = SkyLight()
        let displayID = try backend.activeDisplayID()
        let switcher = SpaceSwitch(backend: backend)
        var nextDirection: Direction? = direction
        var completedSwitches = 0
        burst.begin()
        do {
            while let step = nextDirection {
                try Task.checkCancellation()
                guard try backend.activeDisplayID() == displayID else {
                    throw FlickError.message(
                        "The active display changed; remaining queued switches were discarded."
                    )
                }
                try await switcher.switchSpace(displayID: displayID, direction: step)
                completedSwitches += 1
                nextDirection = burst.takeNext()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FlickError.message(
                "Switch sequence stopped after \(completedSwitches) completed step(s). \(error.localizedDescription)"
            )
        }
        return
            "Switched \(completedSwitches) Space(s) on the active display; destination and visibility confirmed. No windows moved."
    }
}
