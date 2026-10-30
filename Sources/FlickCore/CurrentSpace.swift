/// The menu-bar indicator follows Mission Control's desktop numbering, not Space IDs.
public enum CurrentSpace: Equatable {
    case desktop(Int)
    case fullscreen
    case unavailable

    public init(displays: [SpaceDisplay], activeDisplayID: String) {
        guard let display = displays.first(where: { $0.id == activeDisplayID }),
            let current = display.spaces.first(where: { $0.id == display.currentSpaceID })
        else {
            self = .unavailable
            return
        }
        if current.isDesktop {
            // Desktop labels continue across displays; fullscreen Spaces have no number.
            let desktops = displays.flatMap(\.spaces).filter(\.isDesktop)
            if let index = desktops.firstIndex(where: { $0.id == current.id }) {
                self = .desktop(index + 1)
            } else {
                self = .unavailable
            }
        } else {
            self = current.type == 4 ? .fullscreen : .unavailable
        }
    }
}
