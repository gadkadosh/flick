import AppKit
import ApplicationServices
import FlickCore
import SkyLightBridge

/// App activation alone misses focus changes between windows of the same application.
@MainActor
final class WindowSwitchFocusObserver: NSObject {
    private let record: (WindowIdentity) -> Void
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var pid: pid_t?

    init(record: @escaping (WindowIdentity) -> Void) {
        self.record = record
        super.init()
    }

    func start() {
        stop()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activated),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        activated()
    }

    @objc private func activated() {
        detach()
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        pid = app.processIdentifier
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        application = element
        var observer: AXObserver?
        if AXObserverCreate(
            app.processIdentifier,
            { _, _, _, context in
                guard let context else { return }
                let owner = Unmanaged<WindowSwitchFocusObserver>.fromOpaque(context)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { owner.refresh() }
            },
            &observer
        ) == .success, let observer {
            self.observer = observer
            for notification in [
                kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
            ] {
                AXObserverAddNotification(
                    observer,
                    element,
                    notification as CFString,
                    Unmanaged.passUnretained(self).toOpaque()
                )
            }
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        refresh()
    }

    private func refresh() {
        guard let pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            let window = WindowSwitchInventory.focusedWindow(pid)
        else { return }
        let id = FlickWindowID(window)
        if id != 0 { record(WindowIdentity(processID: pid, windowID: id)) }
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        application = nil
        pid = nil
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()
    }
}
