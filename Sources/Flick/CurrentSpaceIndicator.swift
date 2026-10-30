import AppKit
import FlickCore

@MainActor
final class CurrentSpaceIndicator: NSObject {
    private let button: NSButton
    private let readSpace: @MainActor () throws -> CurrentSpace
    private let notifications: NotificationCenter
    private var timer: Timer?
    private var displayedSpace: CurrentSpace?

    init(
        button: NSButton,
        notifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        readSpace: @escaping @MainActor () throws -> CurrentSpace = {
            let backend = SkyLight()
            return try CurrentSpace(
                displays: backend.displays(),
                activeDisplayID: backend.activeDisplayID()
            )
        }
    ) {
        self.button = button
        self.notifications = notifications
        self.readSpace = readSpace
    }

    func start(pollInterval: TimeInterval = 1) {
        stop()
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
        ] {
            notifications.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
        // Reordering desktops and changing the active menu-bar display need not
        // emit a Space-change notification. Poll as well, including while menus track.
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = pollInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        notifications.removeObserver(self)
    }

    @objc func refresh() {
        let space = (try? readSpace()) ?? .unavailable
        guard space != displayedSpace else { return }
        displayedSpace = space

        let image: NSImage?
        let label: String
        switch space {
        case .desktop(let number):
            label = "Flick — Desktop \(number)"
            image = Self.boxedNumber(number)
        case .fullscreen:
            label = "Flick — Fullscreen or Split View Space"
            image = NSImage(
                systemSymbolName: "arrow.up.left.and.arrow.down.right",
                accessibilityDescription: label
            )
        case .unavailable:
            label = "Flick — Current Space unavailable"
            image = NSImage(
                systemSymbolName: "arrow.left.arrow.right",
                accessibilityDescription: label
            )
        }
        image?.accessibilityDescription = label
        button.image = image
        button.setAccessibilityLabel(label)
    }

    private static func boxedNumber(_ number: Int) -> NSImage {
        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let textSize = text.size(withAttributes: attributes)
        let size = NSSize(width: max(18, ceil(textSize.width) + 6), height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            let border = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.75, dy: 0.75),
                xRadius: 3,
                yRadius: 3
            )
            border.lineWidth = 1.5
            border.stroke()
            text.draw(
                at: NSPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
