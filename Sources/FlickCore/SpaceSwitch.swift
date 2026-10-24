import Foundation

@MainActor
public struct SpaceSwitch {
    private let backend: any SpaceBackend
    private let confirmation: SpaceConfirmation

    public init(backend: any SpaceBackend, pause: (() async -> Void)? = nil) {
        self.backend = backend
        confirmation = SpaceConfirmation(pause: pause)
    }

    @discardableResult
    public func switchSpace(displayID: String, direction: Direction) async throws -> SpaceRoute {
        try Task.checkCancellation()
        guard let display = try backend.displays().first(where: { $0.id == displayID }) else {
            throw SpaceMoveError.invalidLayout
        }
        let route = try SpaceRoute(display: display, direction: direction)
        try backend.activate(spaceID: route.destinationID, on: route.displayID)
        guard
            try await confirmation.waitUntil({
                try backend.displays().first(where: { $0.id == route.displayID })?.currentSpaceID
                    == route.destinationID
            })
        else {
            throw SpaceMoveError.switchNotConfirmed(route.destinationID)
        }
        return route
    }
}

/// Finish confirming an already-dispatched operation even when quitting cancels
/// the task. The next step checks cancellation before dispatching anything.
@MainActor
struct SpaceConfirmation {
    private let pause: () async -> Void

    init(pause: (() async -> Void)?) {
        self.pause =
            pause ?? {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) {
                        continuation.resume()
                    }
                }
            }
    }

    func waitUntil(_ condition: () throws -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while true {
            if try condition() { return true }
            guard ContinuousClock.now < deadline else { return false }
            await pause()
        }
    }
}
