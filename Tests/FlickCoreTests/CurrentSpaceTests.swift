import Testing

@testable import FlickCore

struct CurrentSpaceTests {
    @Test func numberingUsesDesktopOrderAndSkipsFullscreenSpaces() {
        let spaces = [Space(id: 90), Space(id: 42, type: 4), Space(id: 7), Space(id: 99)]
        let display = SpaceDisplay(id: "main", currentSpaceID: 7, spaces: spaces)
        #expect(CurrentSpace(displays: [display], activeDisplayID: "main") == .desktop(2))
        let fullscreen = SpaceDisplay(id: "main", currentSpaceID: 42, spaces: spaces)
        #expect(CurrentSpace(displays: [fullscreen], activeDisplayID: "main") == .fullscreen)
    }

    @Test func activeMenuBarDisplaySelectsTheSpaceWithGlobalDesktopNumbering() {
        let first = SpaceDisplay(
            id: "first",
            currentSpaceID: 10,
            spaces: [Space(id: 10), Space(id: 11, type: 4), Space(id: 12)]
        )
        let second = SpaceDisplay(
            id: "second",
            currentSpaceID: 21,
            spaces: [Space(id: 20), Space(id: 21)]
        )
        #expect(CurrentSpace(displays: [first, second], activeDisplayID: "first") == .desktop(1))
        #expect(CurrentSpace(displays: [first, second], activeDisplayID: "second") == .desktop(4))
    }

    @Test func additionsRemovalsAndReorderingRecalculateTheNumber() {
        for (ids, number): ([UInt64], Int) in [
            ([10, 20, 30], 2), ([30, 10, 20], 3), ([20, 30, 10], 1),
            ([10, 30, 40, 20], 4), ([20], 1),
        ] {
            let display = SpaceDisplay(
                id: "main",
                currentSpaceID: 20,
                spaces: ids.map { Space(id: $0) }
            )
            #expect(CurrentSpace(displays: [display], activeDisplayID: "main") == .desktop(number))
        }
    }

    @Test func missingDisplayCurrentSpaceAndUnknownTypesDoNotGuess() {
        let desktop = SpaceDisplay(id: "main", currentSpaceID: 10, spaces: [Space(id: 10)])
        #expect(CurrentSpace(displays: [], activeDisplayID: "main") == .unavailable)
        #expect(CurrentSpace(displays: [desktop], activeDisplayID: "missing") == .unavailable)
        for spaces in [[Space(id: 11)], [Space(id: 10, type: 99)]] {
            let display = SpaceDisplay(id: "main", currentSpaceID: 10, spaces: spaces)
            #expect(CurrentSpace(displays: [display], activeDisplayID: "main") == .unavailable)
        }
    }
}
