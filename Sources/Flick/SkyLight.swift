import ApplicationServices
import FlickCore
import SkyLightBridge

/// Dispatch is not proof of success; the core reads back the resulting state.
@MainActor
struct SkyLight: SpaceBackend {
    func displays() throws -> [SpaceDisplay] {
        guard let raw = FlickCopyDisplays() as? [[String: Any]] else {
            throw SpaceMoveError.invalidLayout
        }
        return try SpaceDisplay.read(raw)
    }

    func activeDisplayID() throws -> String {
        guard let id = FlickCopyActiveDisplay() as String?, !id.isEmpty else {
            throw FlickError.message(
                "Could not identify macOS's active display. No desktop switch was requested."
            )
        }
        return id
    }

    func spaces(for windowID: UInt32) throws -> [UInt64] {
        guard let raw = FlickCopyWindowSpaces(windowID) as? [NSNumber] else {
            throw FlickError.message("Could not read the window's Space membership.")
        }
        return raw.map(\.uint64Value)
    }

    func move(windowID: UInt32, to spaceID: UInt64) throws {
        guard FlickMoveWindow(windowID, spaceID) else {
            throw FlickError.message("macOS rejected the direct window move.")
        }
    }

    func activate(spaceID: UInt64, on displayID: String) throws {
        guard FlickActivateSpace(displayID as CFString, spaceID) else {
            throw FlickError.message("macOS rejected the desktop switch.")
        }
    }
}
