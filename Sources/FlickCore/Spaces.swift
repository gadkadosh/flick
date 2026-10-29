import Foundation

public struct Space: Equatable {
    public let id: UInt64
    public let type: Int
    public var isDesktop: Bool { type == 0 }

    public init(id: UInt64, type: Int = 0) {
        self.id = id
        self.type = type
    }
}

public struct SpaceDisplay: Equatable {
    public let id: String
    public let currentSpaceID: UInt64
    public let spaces: [Space]

    public init(id: String, currentSpaceID: UInt64, spaces: [Space]) {
        self.id = id
        self.currentSpaceID = currentSpaceID
        self.spaces = spaces
    }

    /// Reject an incomplete snapshot rather than guessing which desktop is next.
    public static func read(_ dictionaries: [[String: Any]]) throws -> [SpaceDisplay] {
        let displays = try dictionaries.map { dictionary in
            guard let id = dictionary["Display Identifier"] as? String, !id.isEmpty,
                let current = dictionary["Current Space"] as? [String: Any],
                let currentID = spaceID(current),
                let rawSpaces = dictionary["Spaces"] as? [[String: Any]], !rawSpaces.isEmpty
            else {
                throw SpaceMoveError.invalidLayout
            }
            let spaces = try rawSpaces.map { raw in
                guard let id = spaceID(raw), let type = raw["type"] as? NSNumber else {
                    throw SpaceMoveError.invalidLayout
                }
                return Space(id: id, type: type.intValue)
            }
            guard spaces.contains(where: { $0.id == currentID }) else {
                throw SpaceMoveError.invalidLayout
            }
            return SpaceDisplay(id: id, currentSpaceID: currentID, spaces: spaces)
        }
        let spaceIDs = displays.flatMap { $0.spaces.map(\.id) }
        guard !displays.isEmpty, Set(displays.map(\.id)).count == displays.count,
            Set(spaceIDs).count == spaceIDs.count
        else { throw SpaceMoveError.invalidLayout }
        return displays
    }

    private static func spaceID(_ dictionary: [String: Any]) -> UInt64? {
        guard let number = (dictionary["ManagedSpaceID"] ?? dictionary["id64"]) as? NSNumber,
            number.int64Value > 0
        else { return nil }
        return number.uint64Value
    }
}

public struct SpaceRoute: Equatable {
    public let displayID: String
    public let sourceID: UInt64
    public let destinationID: UInt64

    public init(displays: [SpaceDisplay], windowSpaces: [UInt64], direction: Direction) throws {
        guard windowSpaces.count == 1, let source = windowSpaces.first,
            let display = displays.first(where: { $0.spaces.contains(where: { $0.id == source }) }),
            let index = display.spaces.firstIndex(where: { $0.id == source })
        else {
            throw SpaceMoveError.unsupportedWindowSpaces
        }
        guard display.currentSpaceID == source else { throw SpaceMoveError.windowNotOnCurrentSpace }
        guard display.spaces[index].isDesktop else { throw SpaceMoveError.unsupportedSpace }
        let next = index + (direction == .next ? 1 : -1)
        guard display.spaces.indices.contains(next) else {
            throw SpaceMoveError.boundary(direction)
        }
        guard display.spaces[next].isDesktop else { throw SpaceMoveError.unsupportedSpace }
        displayID = display.id
        sourceID = source
        destinationID = display.spaces[next].id
    }
}

public enum SpaceMoveError: Error, Equatable, LocalizedError {
    case invalidLayout
    case unsupportedWindowSpaces
    case windowNotOnCurrentSpace
    case unsupportedSpace
    case boundary(Direction)
    case moveNotConfirmed(UInt64)
    case followNotConfirmed(UInt64)

    public var errorDescription: String? {
        switch self {
        case .invalidLayout: return "Could not read a complete desktop Space layout."
        case .unsupportedWindowSpaces:
            return
                "The window must belong to exactly one desktop Space. Pinned and all-desktop windows are not supported."
        case .windowNotOnCurrentSpace:
            return "The window is no longer on the current Space. Try again after focusing it."
        case .unsupportedSpace:
            return
                "Only adjacent ordinary desktop Spaces are supported. Flick does not skip fullscreen or Split View Spaces."
        case .boundary(let direction):
            return "There is no \(direction.label) desktop Space on this display."
        case .moveNotConfirmed:
            return
                "The window's destination Space could not be confirmed. Flick did not request a desktop switch."
        case .followNotConfirmed:
            return
                "The window moved, but following it could not be confirmed. Remaining queued moves were discarded."
        }
    }
}
