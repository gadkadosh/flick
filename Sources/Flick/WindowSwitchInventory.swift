import AppKit
import ApplicationServices
import Carbon
import FlickCore
import SkyLightBridge

struct WindowSwitchTarget {
    let id: WindowIdentity
    let title: String
    let appName: String
    let icon: NSImage?
    let focus: @MainActor () async throws -> Void
}

struct WindowSwitchSnapshot {
    let targets: [WindowSwitchTarget]
    let focused: WindowIdentity?
    let screenFrame: NSRect
}

/// AX calls run outside the event loop: an unresponsive application must not stall keyboard capture.
@MainActor
enum WindowSwitchInventory {
    private struct AccessibleWindow: @unchecked Sendable {
        let candidate: WindowSwitchCandidate
        let element: AXUIElement
        let title: String
    }

    private struct Discovery: @unchecked Sendable {
        let windows: [AccessibleWindow]
        let focused: WindowIdentity?
        let display: WindowSwitchDisplay
    }

    static func capture() async throws -> WindowSwitchSnapshot {
        guard AXIsProcessTrusted() else {
            throw FlickError.message("Enable Accessibility for Flick before using ⌥Tab.")
        }
        let displays = try displayLayout()
        let activeID = try? SkyLight().activeDisplayID()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let pids = apps.map(\.processIdentifier)
        let task = Task.detached(priority: .userInitiated) {
            try discover(pids: pids, frontPID: frontPID, displays: displays, fallbackID: activeID)
        }
        let discovery = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        guard let screen = NSScreen.screens.first(where: { displayID($0) == discovery.display.id })
        else {
            throw FlickError.message("The switcher’s display was disconnected.")
        }
        let targets = discovery.windows.compactMap { window -> WindowSwitchTarget? in
            guard
                let app = apps.first(where: {
                    $0.processIdentifier == window.candidate.id.processID
                })
            else {
                return nil
            }
            return WindowSwitchTarget(
                id: window.candidate.id,
                title: window.title,
                appName: app.localizedName ?? "Application",
                icon: app.icon,
                focus: { try await focus(window, app: app, display: discovery.display) }
            )
        }
        return WindowSwitchSnapshot(
            targets: targets,
            focused: discovery.focused,
            screenFrame: screen.frame
        )
    }

    private static func displayID(_ screen: NSScreen) -> String? {
        guard
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func displayLayout() throws -> [WindowSwitchDisplay] {
        let spaces = try SkyLight().displays()
        let displays = NSScreen.screens.compactMap { screen -> WindowSwitchDisplay? in
            guard let id = displayID(screen), let space = spaces.first(where: { $0.id == id }),
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber
            else {
                return nil
            }
            return WindowSwitchDisplay(
                id: id,
                frame: CGDisplayBounds(number.uint32Value),
                spaceID: space.currentSpaceID
            )
        }
        guard displays.count == NSScreen.screens.count, !displays.isEmpty else {
            throw FlickError.message(
                "Could not match displays to their visible Spaces. This display/Space configuration is not supported."
            )
        }
        return displays
    }

    nonisolated private static func discover(
        pids: [pid_t],
        frontPID: pid_t?,
        displays: [WindowSwitchDisplay],
        fallbackID: String?
    ) throws -> Discovery {
        let visible = visibleWindows()
        let focusedElement = frontPID.flatMap { focusedWindow($0) }
        let focused = focusedElement.flatMap { window -> WindowIdentity? in
            let id = FlickWindowID(window)
            guard id != 0, let frontPID else { return nil }
            return WindowIdentity(processID: frontPID, windowID: id)
        }
        let focusedDisplay = focusedElement.flatMap { frame($0) }
            .flatMap { WindowSwitchDisplay.containing($0, in: displays) }
        guard let display = focusedDisplay ?? displays.first(where: { $0.id == fallbackID }) else {
            throw FlickError.message("Could not determine the current display.")
        }
        var windows: [UInt32: AccessibleWindow] = [:]
        let visibleIDs = Set(visible.map { $0.id })
        let visiblePIDs = Set(visible.map { $0.pid })
        for pid in pids where visiblePIDs.contains(pid) {
            try Task.checkCancellation()
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.15)
            guard let elements = attribute(application, kAXWindowsAttribute) as? [AXUIElement]
            else { continue }
            for element in elements {
                try Task.checkCancellation()
                let id = FlickWindowID(element)
                guard visibleIDs.contains(id), isOrdinary(element), let rect = frame(element),
                    let raw = FlickCopyWindowSpaces(id) as? [NSNumber]
                else { continue }
                let candidate = WindowSwitchCandidate(
                    id: WindowIdentity(processID: pid, windowID: id),
                    frame: rect,
                    spaces: raw.map(\.uint64Value)
                )
                guard candidate.belongs(to: display, among: displays) else { continue }
                windows[id] = AccessibleWindow(
                    candidate: candidate,
                    element: element,
                    title: attribute(element, kAXTitleAttribute) as? String ?? "Untitled Window"
                )
            }
        }
        return Discovery(
            windows: visible.compactMap { windows[$0.id] },
            focused: focused,
            display: display
        )
    }

    private static func focus(
        _ window: AccessibleWindow,
        app: NSRunningApplication,
        display: WindowSwitchDisplay
    ) async throws {
        try Task.checkCancellation()
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            throw FlickError.message(
                "Window switching is unavailable during Secure Keyboard Entry or without Accessibility permission."
            )
        }
        let layout = try displayLayout()
        let id = window.candidate.id.windowID
        guard layout.contains(display), !app.isTerminated, !app.isHidden,
            visibleWindows().contains(where: { $0.id == id && $0.pid == app.processIdentifier }),
            FlickWindowID(window.element) == id, isOrdinary(window.element),
            let rect = frame(window.element),
            let spaces = FlickCopyWindowSpaces(id) as? [NSNumber],
            WindowSwitchCandidate(
                id: window.candidate.id,
                frame: rect,
                spaces: spaces.map(\.uint64Value)
            )
            .belongs(to: display, among: layout)
        else {
            throw FlickError.message(
                "The selected window or display changed. No window switch was requested."
            )
        }
        // Make this window the app's main window before activation, rather than activating all its windows.
        _ = AXUIElementSetAttributeValue(
            window.element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        guard AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success,
            app.activate(options: [])
        else {
            throw FlickError.message("macOS could not activate the selected window.")
        }
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        for _ in 0..<10 {
            try Task.checkCancellation()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                let focused = focusedWindow(app.processIdentifier), FlickWindowID(focused) == id
            {
                guard try displayLayout().contains(display) else {
                    throw FlickError.message(
                        "The visible Space or display changed during window activation."
                    )
                }
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw FlickError.message("macOS did not confirm focus on the selected window.")
    }

    nonisolated static func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let value = attribute(app, kAXFocusedWindowAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef?
    {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    nonisolated private static func isOrdinary(_ window: AXUIElement) -> Bool {
        (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole
            && (attribute(window, kAXMinimizedAttribute) as? Bool) != true
            && (attribute(window, "AXFullScreen") as? Bool) != true
    }

    nonisolated private static func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute),
            let size = attribute(window, kAXSizeAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    nonisolated private static func visibleWindows() -> [(id: UInt32, pid: pid_t)] {
        guard
            let rows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            )
                as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let id = row[kCGWindowNumber as String] as? NSNumber,
                let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
                (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0
            else { return nil }
            return (id.uint32Value, pid.int32Value)
        }
    }
}
