import AppKit
import FlickCore

@MainActor
final class WindowSwitchPanel {
    private var panel: NSPanel?

    func show(_ snapshot: WindowSwitchSnapshot, selected: WindowIdentity) {
        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.collectionBehavior = [
                .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle,
            ]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.setAccessibilityLabel("Flick window switcher")
            self.panel = panel
        }
        let width = min(500, snapshot.screenFrame.width - 48)
        let rowHeight: CGFloat = 56
        let listHeight = min(
            CGFloat(snapshot.targets.count) * rowHeight,
            snapshot.screenFrame.height * 0.6
        )
        let height = listHeight + 76
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        let heading = label(
            "Windows on this display",
            font: .systemFont(ofSize: 13, weight: .semibold)
        )
        heading.frame = NSRect(x: 20, y: height - 32, width: width - 40, height: 20)
        effect.addSubview(heading)
        let hint = label(
            "⌥Tab next · ⇧ reverse · release ⌥ to select · Esc cancel",
            font: .systemFont(ofSize: 11)
        )
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 10, width: width - 40, height: 18)
        effect.addSubview(hint)
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 36, width: width - 16, height: listHeight))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = snapshot.targets.count > Int(listHeight / rowHeight)
        let document = WindowSwitchDocument(
            frame: NSRect(
                x: 0,
                y: 0,
                width: width - 16,
                height: CGFloat(snapshot.targets.count) * rowHeight
            )
        )
        var selectedRect = NSRect.zero
        for (index, target) in snapshot.targets.enumerated() {
            let row = NSView(
                frame: NSRect(
                    x: 4,
                    y: CGFloat(index) * rowHeight + 2,
                    width: width - 32,
                    height: rowHeight - 4
                )
            )
            if target.id == selected {
                row.wantsLayer = true
                row.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
                row.layer?.cornerRadius = 9
                selectedRect = row.frame
            }
            let icon = NSImageView(frame: NSRect(x: 10, y: 10, width: 32, height: 32))
            icon.image = target.icon
            row.addSubview(icon)
            let title = label(
                target.title.isEmpty ? "Untitled Window" : target.title,
                font: .systemFont(ofSize: 13, weight: .medium)
            )
            title.frame = NSRect(x: 54, y: 27, width: row.frame.width - 68, height: 18)
            let app = label(target.appName, font: .systemFont(ofSize: 11))
            app.textColor =
                target.id == selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
            app.frame = NSRect(x: 54, y: 8, width: row.frame.width - 68, height: 16)
            if target.id == selected { title.textColor = .alternateSelectedControlTextColor }
            row.addSubview(title)
            row.addSubview(app)
            document.addSubview(row)
        }
        scroll.documentView = document
        effect.addSubview(scroll)
        panel.contentView = effect
        panel.setFrame(
            NSRect(
                x: snapshot.screenFrame.midX - width / 2,
                y: snapshot.screenFrame.midY - height / 2,
                width: width,
                height: height
            ),
            display: true
        )
        document.scrollToVisible(selectedRect)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func label(_ title: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = font
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        return field
    }
}

private final class WindowSwitchDocument: NSView {
    override var isFlipped: Bool { true }
}
