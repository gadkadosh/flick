import AppKit
import ApplicationServices
import FlickCore

/// Experimental public-API backend: drag a title bar while invoking the user's
/// actual Mission Control shortcut. No private WindowServer calls or SIP changes.
@MainActor
final class WindowMover {
    private var observer: NSObjectProtocol?
    private var spaceChanges = 0
    private(set) var busy = false
    private(set) var lastPreparationMilliseconds: Int?
    private var burst = WindowMoveBurst()
    private var burstShortcuts: [Direction: SpaceShortcut] = [:]
    var pendingMoves: Int { burst.pendingCount }

    /// Accept only while the original window is held. Never replay a shortcut
    /// against whichever unrelated window becomes focused after a drop.
    func enqueue(_ direction: Direction) -> Bool {
        guard busy, burstShortcuts[direction] != nil else { return false }
        return burst.enqueue(direction)
    }

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanges += 1 }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    func move(_ direction: Direction) async throws -> String {
        guard !busy else { throw FlickError.message("A move is already in progress.") }
        busy = true
        lastPreparationMilliseconds = nil
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer {
            burst.close()
            burstShortcuts.removeAll()
            busy = false
        }
        guard AXIsProcessTrusted() else {
            throw FlickError.message("Enable Flick in System Settings → Privacy & Security → Accessibility, then try again.")
        }
        let hotkeys = symbolicHotkeys()
        guard SpaceShortcut.read(direction: direction, from: hotkeys) != nil else {
            throw FlickError.message("Enable ‘Move \(direction.label) a space’ in System Settings → Keyboard → Keyboard Shortcuts → Mission Control.")
        }
        burstShortcuts = Dictionary(uniqueKeysWithValues: Direction.allCases.compactMap { direction in
            SpaceShortcut.read(direction: direction, from: hotkeys).map { (direction, $0) }
        })
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
        guard let origin = point(window), let size = windowSize(window),
              let titlePoint = draggablePoint(window, origin: origin, size: size) else {
            throw FlickError.message("Could not find a safe, visible title-bar drag point. Try a different window; borderless windows are not supported.")
        }
        let windowID = visibleWindowID(pid: app.processIdentifier, origin: origin, size: size)
        var movable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable) == .success,
              movable.boolValue else {
            throw FlickError.message("This window does not support repositioning through Accessibility.")
        }
        guard let source = SyntheticInput.makeSource(),
              let cursor = CGEvent(source: nil)?.location else {
            throw FlickError.message("Could not create input events.")
        }

        // Modifiers may stay held. Synthetic events carry their own exact flags.
        // Never interfere with an existing user mouse drag.
        try requireReleasedMouseButtons()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let stillFocused = attribute(application, kAXFocusedWindowAttribute),
              CFEqual(stillFocused, window) else {
            throw FlickError.message("Focus changed before the move started; try again.")
        }
        let draggedPoint = CGPoint(x: titlePoint.x + 6, y: titlePoint.y)
        // Allocate all mouse events before pressing; cleanup must always be possible.
        guard let down = SyntheticInput.mouse(.leftMouseDown, at: titlePoint, source: source),
              let drag = SyntheticInput.mouse(.leftMouseDragged, at: draggedPoint, source: source),
              let up = SyntheticInput.mouse(.leftMouseUp, at: draggedPoint, source: source),
              let restoreCursor = SyntheticInput.mouse(.mouseMoved, at: cursor, source: source) else {
            throw FlickError.message("Could not create mouse events.")
        }
        var held = false
        var started = false
        defer {
            if held { up.post(tap: .cghidEventTap) }
            if started {
                // Undo the tiny drag displacement without resizing the window.
                var oldPosition = origin
                if let value = AXValueCreate(.cgPoint, &oldPosition) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                }
                restoreCursor.post(tap: .cghidEventTap)
            }
        }
        burst.begin()
        down.post(tap: .cghidEventTap)
        held = true
        started = true
        try await pause(MoveTiming.pressToDrag)
        drag.post(tap: .cghidEventTap)
        try await pause(MoveTiming.dragToSwitch)
        var nextDirection: Direction? = direction
        var navigationError: Error?
        do {
            while let step = nextDirection {
                guard let shortcut = burstShortcuts[step] else {
                    throw FlickError.message("The requested Space-switching shortcut is unavailable.")
                }
                let before = spaceChanges
                let switchRequestedAt = ProcessInfo.processInfo.systemUptime
                if lastPreparationMilliseconds == nil {
                    lastPreparationMilliseconds = Int((switchRequestedAt - startedAt) * 1_000)
                }
                try send(shortcut, source: source)
                guard try await waitForSpaceChange(after: before) else {
                    throw FlickError.message("The last Space switch was not confirmed. You may be at the desktop boundary, or macOS may have ignored the gesture.")
                }
                burst.recordCompleted(step)
                try await settleSwitch(requestedAt: switchRequestedAt)
                drag.post(tap: .cghidEventTap)
                // Keep the same window held for another queued step: no second
                // title-bar lookup, drop, focus change, or mouse-down delay.
                nextDirection = burst.takeNext()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            navigationError = error
        }
        burst.close() // No request can race mouse-up and target another window.
        drag.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        held = false
        try await pause(MoveTiming.dropToVerify)

        // A navigation notification alone does not prove the window moved. When
        // public window metadata identifies it unambiguously, check visibility
        // after the drop. This is still not an exact Space-membership query.
        let visibleAtDestination = windowID.flatMap(isWindowVisible)
        // Successful moves always follow the window. Retrace only as error
        // recovery if the window is missing after the drop, never as a UX mode.
        var rolledBack = false
        if visibleAtDestination == false, !burst.completed.isEmpty {
            for step in burst.rollbackPath {
                guard let reverse = burstShortcuts[step] else {
                    throw FlickError.message("The window was not visible after the drop, and no shortcut is available to recover the starting Space.")
                }
                let beforeReturn = spaceChanges
                let returnRequestedAt = ProcessInfo.processInfo.systemUptime
                try send(reverse, source: source)
                guard try await waitForSpaceChange(after: beforeReturn) else {
                    throw FlickError.message("The window was not visible after the drop, and recovering the starting Space was not confirmed.")
                }
                try await settleSwitch(requestedAt: returnRequestedAt)
            }
            rolledBack = true
        }
        if let navigationError {
            throw FlickError.message("Move sequence stopped after \(burst.completed.count) confirmed Space switches. \(navigationError.localizedDescription)\(rolledBack ? " Recovered the starting Space." : "") Remaining queued presses were discarded.")
        }
        if visibleAtDestination == false {
            throw FlickError.message("The Space switched, but the window was not visible after dropping it. macOS may have ignored the drag. \(rolledBack ? "Flick recovered the starting Space." : "The starting Space was not recovered.")")
        }
        let verification = visibleAtDestination == true ? "window visible after drop" : "window move not verified"
        return "Move sequence finished: \(burst.completed.count) Space switch(es); \(verification)."
    }

    private func visibleWindowID(pid: pid_t, origin: CGPoint, size: CGSize) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let matches = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(rect.minX - origin.x) < 2 && abs(rect.minY - origin.y) < 2
                && abs(rect.width - size.width) < 2 && abs(rect.height - size.height) < 2
        }
        guard matches.count == 1 else { return nil }
        return (matches[0][kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }

    private func isWindowVisible(_ id: CGWindowID) -> Bool? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }
    }

    private func requireReleasedMouseButtons() throws {
        let buttons = CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
            || CGEventSource.buttonState(.combinedSessionState, button: .center)
        guard !buttons else {
            throw FlickError.message("Release the mouse buttons before moving a window. Modifier keys can stay held.")
        }
    }

    private func settleSwitch(requestedAt: Double) async throws {
        let remaining = MoveTiming.remainingSwitchDelay(requestedAt: requestedAt, now: ProcessInfo.processInfo.systemUptime)
        if remaining > 0 { try await pause(remaining) }
    }

    private func waitForSpaceChange(after count: Int) async throws -> Bool {
        for _ in 0..<40 {
            if spaceChanges > count { return true }
            try await pause(0.05)
        }
        return spaceChanges > count
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func send(_ shortcut: SpaceShortcut, source: CGEventSource) throws {
        guard let events = SyntheticInput.keyStroke(shortcut, source: source) else {
            throw FlickError.message("Could not create keyboard events.")
        }
        events.down.post(tap: .cghidEventTap)
        events.up.post(tap: .cghidEventTap)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func point(_ element: AXUIElement) -> CGPoint? {
        guard let raw = attribute(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(raw as! AXValue, .cgPoint, &point) ? point : nil
    }

    private func windowSize(_ element: AXUIElement) -> CGSize? {
        guard let raw = attribute(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(raw as! AXValue, .cgSize, &size) ? size : nil
    }

    private func draggablePoint(_ window: AXUIElement, origin: CGPoint, size: CGSize) -> CGPoint? {
        guard size.width > 200, size.height > 80 else { return nil }
        var candidates: [(CGPoint, Bool)] = []
        if let title = attribute(window, kAXTitleUIElementAttribute), CFGetTypeID(title) == AXUIElementGetTypeID() {
            let element = title as! AXUIElement
            if let p = point(element), let s = windowSize(element), s.width > 0, s.height > 0 {
                let center = CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
                if center.y >= origin.y && center.y < origin.y + 32 {
                    candidates.append((center, true))
                }
            }
        }
        // Hit-test empty title-bar areas; never click a tab, toolbar button, or control.
        candidates += [0.5, 0.35, 0.75].map {
            (CGPoint(x: origin.x + size.width * $0, y: origin.y + 12), false)
        }
        let system = AXUIElementCreateSystemWide()
        for (candidate, isTitle) in candidates {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(candidate.x), Float(candidate.y), &hit) == .success,
                  let hit else { continue }
            let role = attribute(hit, kAXRoleAttribute) as? String
            let hitWindow = role == kAXWindowRole ? hit : attribute(hit, kAXWindowAttribute)
            guard let hitWindow, CFEqual(hitWindow, window) else { continue }
            if role == kAXWindowRole || (isTitle && role == kAXStaticTextRole) { return candidate }
        }
        return nil
    }
}
