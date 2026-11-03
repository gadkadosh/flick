import AppKit
import FlickCore

@MainActor
final class WindowSwitcher {
    typealias Capture = @MainActor () async throws -> WindowSwitchSnapshot
    private let capture: Capture
    private let present: @MainActor (WindowSwitchSnapshot, WindowIdentity) -> Void
    private let dismiss: @MainActor () -> Void
    private let canBegin: @MainActor () -> Bool
    private let report: @MainActor (String) -> Void
    private var history = WindowFocusHistory()
    private var snapshot: WindowSwitchSnapshot?
    private var session: WindowSwitchSession?
    private var commands: [WindowSwitchKeys.Command] = []
    private var task: Task<Void, Never>?
    private var generation = 0
    private let input = WindowSwitchInput()
    private var focusObserver: WindowSwitchFocusObserver?
    var busy: Bool { task != nil || session != nil || !commands.isEmpty }

    init(
        capture: @escaping Capture = WindowSwitchInventory.capture,
        present: @escaping @MainActor (WindowSwitchSnapshot, WindowIdentity) -> Void,
        dismiss: @escaping @MainActor () -> Void,
        canBegin: @escaping @MainActor () -> Bool,
        report: @escaping @MainActor (String) -> Void
    ) {
        self.capture = capture
        self.present = present
        self.dismiss = dismiss
        self.canBegin = canBegin
        self.report = report
    }

    func start() throws {
        input.onCommand = { [weak self] in self?.receive($0) }
        input.onFailure = { [weak self] in self?.report($0) }
        input.isBusy = { [weak self] in self?.busy == true }
        try input.start()
        if focusObserver == nil {
            focusObserver = WindowSwitchFocusObserver { [weak self] in self?.history.record($0) }
            focusObserver?.start()
        }
    }

    func stop() {
        input.stop()
        focusObserver?.stop()
        focusObserver = nil
        receive(.cancel)
    }

    func receive(_ command: WindowSwitchKeys.Command) {
        if command == .cancel {
            generation += 1
            task?.cancel()
            task = nil
            commands.removeAll()
            snapshot = nil
            session = nil
            dismiss()
            return
        }
        commands.append(command)
        drain()
    }

    private func drain() {
        guard task == nil else { return }
        while !commands.isEmpty {
            switch commands.removeFirst() {
            case .begin(let backwards):
                guard canBegin(), session == nil else {
                    report("Wait for the current operation before switching windows.")
                    continue
                }
                let token = generation
                task = Task {
                    do {
                        let captured = try await capture()
                        try Task.checkCancellation()
                        guard token == generation else { return }
                        if let focused = captured.focused { history.record(focused) }
                        let ordered = history.ordered(captured.targets.map(\.id))
                        guard
                            let selection = WindowSwitchSession(
                                windows: ordered,
                                focused: captured.focused,
                                backwards: backwards
                            )
                        else {
                            throw FlickError.message(
                                "No eligible windows on this display’s visible Space."
                            )
                        }
                        let targets = Dictionary(
                            uniqueKeysWithValues: captured.targets.map { ($0.id, $0) }
                        )
                        let sorted = WindowSwitchSnapshot(
                            targets: ordered.compactMap { targets[$0] },
                            focused: captured.focused,
                            screenFrame: captured.screenFrame
                        )
                        snapshot = sorted
                        session = selection
                        present(sorted, selection.selected)
                    } catch {
                        guard token == generation else { return }
                        if !(error is CancellationError) { report(error.localizedDescription) }
                    }
                    guard token == generation else { return }
                    task = nil
                    drain()
                }
                return
            case .advance(let backwards):
                session?.advance(backwards: backwards)
                if let snapshot, let session { present(snapshot, session.selected) }
            case .commit:
                guard let snapshot, let session,
                    let target = snapshot.targets.first(where: { $0.id == session.selected })
                else { continue }
                self.snapshot = nil
                self.session = nil
                dismiss()
                let token = generation
                task = Task {
                    do {
                        try await target.focus()
                        try Task.checkCancellation()
                        guard token == generation else { return }
                        history.record(target.id)
                        report("Switched to \(target.appName) — \(target.title).")
                    } catch {
                        guard token == generation else { return }
                        if !(error is CancellationError) { report(error.localizedDescription) }
                    }
                    guard token == generation else { return }
                    task = nil
                    drain()
                }
                return
            case .cancel: break  // Handled immediately in receive, including while discovery is suspended.
            }
        }
    }
}
