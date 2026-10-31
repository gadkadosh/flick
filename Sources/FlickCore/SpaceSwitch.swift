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
        return try await activate(route)
    }

    @discardableResult
    public func jumpToDesktop(_ number: Int) async throws -> SpaceRoute {
        try Task.checkCancellation()
        let route = try SpaceRoute(displays: backend.displays(), desktopNumber: number)
        return try await activate(route)
    }

    private func activate(_ route: SpaceRoute) async throws -> SpaceRoute {
        if route.sourceID != route.destinationID {
            try backend.activate(spaceID: route.destinationID, on: route.displayID)
        }
        guard
            try await confirmation.waitUntil({
                try confirmation.destinationIsVisible(route, using: backend)
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

    func destinationIsVisible(_ route: SpaceRoute, using backend: any SpaceBackend) throws -> Bool {
        guard let display = try backend.displays().first(where: { $0.id == route.displayID }),
            display.currentSpaceID == route.destinationID
        else { return false }
        let visible = Set(try backend.visibleSpaces())
        return display.spaces.filter { visible.contains($0.id) }.map(\.id) == [route.destinationID]
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
