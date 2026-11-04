import AppKit
import ApplicationServices
import FlickCore

/// App activation alone misses focus changes between windows of the same application.
@MainActor
final class WindowSwitchFocusObserver: NSObject {
    private struct Observation: @unchecked Sendable {
        let application: AXUIElement
        let observer: AXObserver?
    }

    private let record: (WindowIdentity) -> Void
    private var observation: Observation?
    private var pid: pid_t?
    private var setupTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

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
        let pid = app.processIdentifier
        self.pid = pid
        let owner = Unmanaged.passUnretained(self)
        setupTask = Task {
            do {
                let observation = try await WindowSwitchInventory.offMain {
                    Self.observe(pid: pid, owner: owner)
                }
                try Task.checkCancellation()
                self.observation = observation
                if let observer = observation?.observer {
                    CFRunLoopAddSource(
                        CFRunLoopGetMain(),
                        AXObserverGetRunLoopSource(observer),
                        .commonModes
                    )
                }
                refresh()
            } catch {
                // Cancellation discards subscriptions that were never attached.
            }
        }
    }

    nonisolated private static func observe(
        pid: pid_t,
        owner: Unmanaged<WindowSwitchFocusObserver>
    ) -> Observation? {
        guard let element = WindowSwitchInventory.bounded(AXUIElementCreateApplication(pid)) else {
            return nil
        }
        var observer: AXObserver?
        if AXObserverCreate(
            pid,
            { _, _, _, context in
                guard let context else { return }
                let owner = Unmanaged<WindowSwitchFocusObserver>.fromOpaque(context)
                    .takeUnretainedValue()
                MainActor.assumeIsolated { owner.refresh() }
            },
            &observer
        ) == .success, let observer {
            for notification in [
                kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
            ] {
                guard !Task.isCancelled else { return nil }
                AXObserverAddNotification(
                    observer,
                    element,
                    notification as CFString,
                    owner.toOpaque()
                )
            }
        }
        return Observation(application: element, observer: observer)
    }

    private func refresh() {
        refreshTask?.cancel()
        guard let pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return
        }
        refreshTask = Task {
            do {
                let id = try await WindowSwitchInventory.offMain {
                    WindowSwitchInventory.focusedWindowID(pid)
                }
                try Task.checkCancellation()
                guard self.pid == pid,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                    let id
                else { return }
                record(WindowIdentity(processID: pid, windowID: id))
            } catch {
                // Cancellation discards stale focus reads.
            }
        }
    }

    private func detach() {
        setupTask?.cancel()
        setupTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        if let observer = observation?.observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observation = nil
        pid = nil
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detach()
    }
}
