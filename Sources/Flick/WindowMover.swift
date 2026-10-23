import AppKit
import ApplicationServices
import FlickCore
import SkyLightBridge

/// The sole adapter for undocumented Space operations. Success means dispatch;
/// SpaceMove reads back membership and the active desktop before reporting it.
@MainActor
private struct SkyLight: SpaceBackend {
    func displays() throws -> [SpaceDisplay] {
        guard let raw = FlickCopyDisplays() as? [[String: Any]] else { throw SpaceMoveError.invalidLayout }
        return try SpaceDisplay.read(raw)
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
            throw FlickError.message("The window moved, but macOS rejected following it.")
        }
    }
}

@MainActor
final class WindowMover {
    private(set) var busy = false
    private var burst = WindowMoveBurst()
    var pendingMoves: Int { burst.pendingCount }

    func enqueue(_ direction: Direction) -> Bool {
        guard busy else { return false }
        return burst.enqueue(direction)
    }

    func move(_ direction: Direction) async throws -> String {
        guard !busy else { throw FlickError.message("A move is already in progress.") }
        busy = true
        defer {
            burst.close()
            busy = false
        }
        guard AXIsProcessTrusted() else {
            throw FlickError.message("Enable Flick in System Settings → Privacy & Security → Accessibility, then try again.")
        }
        guard FlickSkyLightAvailable() else {
            throw FlickError.message("Direct Space moves are unavailable on this macOS version. Flick requires compatible SkyLight operations and does not fall back to dragging.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw FlickError.message("Focus a window in another app first.")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let value = attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw FlickError.message("The focused app has no accessible window.")
        }
        let window = value as! AXUIElement
        guard (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
              (attribute(window, "AXFullScreen") as? Bool) != true,
              (attribute(window, kAXMinimizedAttribute) as? Bool) != true else {
            throw FlickError.message("Only ordinary desktop windows are supported, not fullscreen windows or dialogs.")
        }
        let windowID = FlickWindowID(window)
        guard windowID != 0 else { throw FlickError.message("Could not identify the focused window.") }
        guard NSEvent.pressedMouseButtons == 0 else {
            throw FlickError.message("Release the mouse buttons before moving a window. Modifier keys can stay held.")
        }
        let mover = SpaceMove(backend: SkyLight())
        var nextDirection: Direction? = direction
        var completedMoves = 0
        burst.begin()
        do {
            while let step = nextDirection {
                try Task.checkCancellation()
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                      let focused = attribute(application, kAXFocusedWindowAttribute), CFEqual(focused, window) else {
                    throw FlickError.message("Focus changed; remaining queued moves were discarded.")
                }
                try await mover.move(windowID: windowID, direction: step)
                completedMoves += 1
                // Raise only after this window and its display have reached the
                // destination, avoiding activation's normal cross-Space slide.
                app.activate(options: [])
                guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
                    throw FlickError.message("The window moved and the desktop switched, but macOS could not refocus it.")
                }
                nextDirection = burst.takeNext()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FlickError.message("Move sequence stopped after \(completedMoves) completed step(s). \(error.localizedDescription)")
        }
        return "Moved and followed the same window across \(completedMoves) Space(s); destination membership confirmed."
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
