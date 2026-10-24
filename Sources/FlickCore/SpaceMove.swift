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
    private let confirmation: SpaceConfirmation

    public init(backend: any SpaceBackend, pause: (() async -> Void)? = nil) {
        self.backend = backend
        confirmation = SpaceConfirmation(pause: pause)
    }

    @discardableResult
    public func move(windowID: UInt32, direction: Direction) async throws -> SpaceRoute {
        try Task.checkCancellation()
        let route = try SpaceRoute(
            displays: backend.displays(),
            windowSpaces: backend.spaces(for: windowID),
            direction: direction
        )
        try backend.move(windowID: windowID, to: route.destinationID)

        // These operations can return successfully without applying anything.
        // Confirm exact membership before following, never just visibility.
        guard
            try await confirmation.waitUntil({
                try backend.spaces(for: windowID) == [route.destinationID]
            })
        else {
            throw SpaceMoveError.moveNotConfirmed(route.destinationID)
        }
        do {
            try backend.activate(spaceID: route.destinationID, on: route.displayID)
        } catch {
            throw SpaceMoveError.followRejected
        }
        guard
            try await confirmation.waitUntil({
                try backend.displays().first(where: { $0.id == route.displayID })?.currentSpaceID
                    == route.destinationID
            })
        else {
            throw SpaceMoveError.followNotConfirmed(route.destinationID)
        }
        return route
    }
}
