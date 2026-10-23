import Foundation

/// Private API calls live in the app adapter; move ordering is testable without
/// changing the user's desktop or posting input.
@MainActor
public protocol SpaceBackend {
    func displays() throws -> [SpaceDisplay]
    func spaces(for windowID: UInt32) throws -> [UInt64]
    func move(windowID: UInt32, to spaceID: UInt64) throws
    func activate(spaceID: UInt64, on displayID: String) throws
}

@MainActor
public struct SpaceMove {
    private let backend: any SpaceBackend
    private let pause: () async -> Void

    public init(backend: any SpaceBackend, pause: (() async -> Void)? = nil) {
        self.backend = backend
        self.pause = pause ?? {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { continuation.resume() }
            }
        }
    }

    @discardableResult
    public func move(windowID: UInt32, direction: Direction) async throws -> SpaceRoute {
        try Task.checkCancellation()
        let route = try SpaceRoute(displays: backend.displays(), windowSpaces: backend.spaces(for: windowID), direction: direction)
        try backend.move(windowID: windowID, to: route.destinationID)

        // These operations can return successfully without applying anything.
        // Confirm exact membership before following, never just visibility.
        guard try await waitUntil({ try backend.spaces(for: windowID) == [route.destinationID] }) else {
            throw SpaceMoveError.moveNotConfirmed(route.destinationID)
        }
        try backend.activate(spaceID: route.destinationID, on: route.displayID)
        guard try await waitUntil({
            try backend.displays().first(where: { $0.id == route.displayID })?.currentSpaceID == route.destinationID
        }) else {
            throw SpaceMoveError.followNotConfirmed(route.destinationID)
        }
        return route
    }

    /// Once requested, finish the bounded move-and-follow transaction even if
    /// quitting cancels the task. Cancellation stops the next queued step.
    private func waitUntil(_ condition: () throws -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while true {
            if try condition() { return true }
            guard ContinuousClock.now < deadline else { return false }
            await pause()
        }
    }
}
