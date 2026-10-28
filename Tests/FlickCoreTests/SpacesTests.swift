import Foundation
import Testing

@testable import FlickCore

struct SpacesTests {
    private let display = SpaceDisplay(
        id: "display",
        currentSpaceID: 90,
        spaces: [Space(id: 12), Space(id: 90), Space(id: 3)]
    )

    @Test func adjacencyUsesDesktopOrderInsteadOfNumericIDs() throws {
        let previous = try SpaceRoute(displays: [display], windowSpaces: [90], direction: .previous)
        let next = try SpaceRoute(displays: [display], windowSpaces: [90], direction: .next)
        #expect(previous.sourceID == 90)
        #expect(previous.destinationID == 12)
        #expect(next.destinationID == 3)
    }

    @Test func routeUsesTheWindowsDisplay() throws {
        let other = SpaceDisplay(
            id: "other",
            currentSpaceID: 40,
            spaces: [Space(id: 40), Space(id: 41)]
        )
        let route = try SpaceRoute(
            displays: [other, display],
            windowSpaces: [90],
            direction: .next
        )
        #expect(route.displayID == "display")
        #expect(route.destinationID == 3)
    }

    @Test func boundariesDoNotWrapOrJumpToAnotherDisplay() {
        #expect(throws: SpaceMoveError.boundary(.next)) {
            try SpaceRoute(
                displays: [SpaceDisplay(id: "display", currentSpaceID: 3, spaces: display.spaces)],
                windowSpaces: [3],
                direction: .next
            )
        }
        #expect(throws: SpaceMoveError.boundary(.previous)) {
            try SpaceRoute(
                displays: [SpaceDisplay(id: "display", currentSpaceID: 12, spaces: display.spaces)],
                windowSpaces: [12],
                direction: .previous
            )
        }
    }

    @Test func fullscreenAndUnknownSpaceTypesAreNotSkipped() {
        for type in [4, 99] {
            let layout = SpaceDisplay(
                id: "display",
                currentSpaceID: 1,
                spaces: [Space(id: 1), Space(id: 2, type: type), Space(id: 3)]
            )
            #expect(throws: SpaceMoveError.unsupportedSpace) {
                try SpaceRoute(displays: [layout], windowSpaces: [1], direction: .next)
            }
        }
    }

    @Test func pinnedMissingAndOffscreenWindowsAreRejected() {
        for membership: [UInt64] in [[], [90, 12], [999]] {
            #expect(throws: SpaceMoveError.unsupportedWindowSpaces) {
                try SpaceRoute(displays: [display], windowSpaces: membership, direction: .next)
            }
        }
        #expect(throws: SpaceMoveError.windowNotOnCurrentSpace) {
            try SpaceRoute(displays: [display], windowSpaces: [12], direction: .next)
        }
    }

    @Test func snapshotReadsBothIDKeysAndPreservesFullscreenTypes() throws {
        let raw: [[String: Any]] = [
            [
                "Display Identifier": "display", "Current Space": ["ManagedSpaceID": 90],
                "Spaces": [
                    ["id64": 12, "type": 0], ["ManagedSpaceID": 90, "type": 0],
                    ["id64": 3, "type": 4],
                ],
            ]
        ]
        let parsed = try SpaceDisplay.read(raw)
        #expect(parsed.count == 1)
        #expect(parsed[0].currentSpaceID == 90)
        #expect(parsed[0].spaces == [Space(id: 12), Space(id: 90), Space(id: 3, type: 4)])
    }

    @Test func malformedSnapshotsFailInsteadOfSilentlyDroppingSpaces() {
        let invalid: [[[String: Any]]] = [
            [], [[:]],
            [["Display Identifier": "d", "Current Space": ["id64": 1], "Spaces": [["id64": 1]]]],
            [
                [
                    "Display Identifier": "d", "Current Space": ["id64": 5],
                    "Spaces": [["id64": 1, "type": 0]],
                ]
            ],
            [
                [
                    "Display Identifier": "d", "Current Space": ["id64": 1],
                    "Spaces": [["id64": 1, "type": 0], ["id64": 1, "type": 0]],
                ]
            ],
            [
                [
                    "Display Identifier": "d", "Current Space": ["id64": -1],
                    "Spaces": [["id64": -1, "type": 0]],
                ]
            ],
        ]
        for raw in invalid {
            #expect(throws: SpaceMoveError.invalidLayout) { try SpaceDisplay.read(raw) }
        }
    }
}
