import AppKit
import ApplicationServices
import FlickCore
import SkyLightBridge

@MainActor
final class WindowMover {
    private(set) var busy = false
    private var burst = DirectionBurst()
    var pendingMoves: Int { burst.pendingCount }

    struct Target {
        let windowID: UInt32
        let isFocused: () -> Bool
        let refocus: () throws -> Void
    }

    typealias ObserveInput =
        @MainActor ([SpaceShortcut], @escaping @MainActor () -> Void) throws ->
        WindowMoveInputMonitor

    private let capture: @MainActor () throws -> Target
    private let moveStep: @MainActor (UInt32, Direction) async throws -> Void
    private let observeInput: ObserveInput

    init(
        capture: @escaping @MainActor () throws -> Target = WindowMover.captureWindow,
        moveStep: @escaping @MainActor (UInt32, Direction) async throws -> Void = {
            windowID,
            direction in
            try await SpaceMove(backend: SkyLight()).move(windowID: windowID, direction: direction)
        },
        observeInput: @escaping ObserveInput = { shortcuts, interrupt in
            try WindowMoveInputMonitor(shortcuts: shortcuts, interrupt: interrupt)
        }
    ) {
        self.capture = capture
        self.moveStep = moveStep
        self.observeInput = observeInput
    }

    func enqueue(_ direction: Direction) -> Bool {
        guard busy else { return false }
        return burst.enqueue(direction)
    }

    func move(_ direction: Direction, preset: ShortcutPreset) async throws -> String {
        guard !busy else { throw FlickError.message("A move is already in progress.") }
        busy = true
        defer {
            burst.close()
            busy = false
        }
        let target = try capture()
        let observation = try observeInput(
            Direction.allCases.map { preset.shortcut(for: $0, action: .moveWindow) }
        ) {
            [weak self] in
            self?.burst.close()
        }
        defer { observation.stop() }
        var nextDirection: Direction? = direction
        var completedMoves = 0
        burst.begin()
        do {
            while let step = nextDirection {
                try Task.checkCancellation()
                try observation.checkAvailability()
                guard burst.accepting, target.isFocused() else {
                    throw FlickError.message(
                        "Focus changed; remaining queued moves were discarded."
                    )
                }
                try await moveStep(target.windowID, step)
                completedMoves += 1
                // Input can change focus while confirmation is suspended. Check
                // the latched interruption BEFORE refocusing can hide that change.
                try observation.checkAvailability()
                guard burst.accepting else {
                    throw FlickError.message(
                        "Other keyboard or mouse input interrupted the sequence; remaining queued moves were discarded."
                    )
                }
                try target.refocus()
                nextDirection = burst.takeNext()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FlickError.message(
                "Move sequence stopped after \(completedMoves) completed step(s). \(error.localizedDescription)"
            )
        }
        return
            "Moved and followed the same window across \(completedMoves) Space(s); destination membership confirmed."
    }

    private static func captureWindow() throws -> Target {
        guard AXIsProcessTrusted() else {
            throw FlickError.message(
                "Enable Flick in System Settings → Privacy & Security → Accessibility, then try again."
            )
        }
        guard FlickSkyLightAvailable() else {
            throw FlickError.message(
                "Direct Space moves are unavailable on this macOS version. Flick requires compatible SkyLight operations and does not fall back to dragging."
            )
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            throw FlickError.message("Focus a window in another app first.")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let value = attribute(application, kAXFocusedWindowAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            throw FlickError.message("The focused app has no accessible window.")
        }
        let window = value as! AXUIElement
        guard (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
            (attribute(window, "AXFullScreen") as? Bool) != true,
            (attribute(window, kAXMinimizedAttribute) as? Bool) != true
        else {
            throw FlickError.message(
                "Only ordinary desktop windows are supported, not fullscreen windows or dialogs."
            )
        }
        let windowID = FlickWindowID(window)
        guard windowID != 0 else {
            throw FlickError.message("Could not identify the focused window.")
        }
        guard NSEvent.pressedMouseButtons == 0 else {
            throw FlickError.message(
                "Release the mouse buttons before moving a window. Modifier keys can stay held."
            )
        }
        return Target(
            windowID: windowID,
            isFocused: {
                guard
                    NSWorkspace.shared.frontmostApplication?.processIdentifier
                        == app.processIdentifier,
                    let focused = attribute(application, kAXFocusedWindowAttribute)
                else { return false }
                return CFEqual(focused, window)
            },
            refocus: {
                // Raise only after both the window and its display reach the destination.
                app.activate(options: [])
                guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
                else {
                    throw FlickError.message(
                        "The window moved and the desktop switched, but macOS could not refocus it."
                    )
                }
            }
        )
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
