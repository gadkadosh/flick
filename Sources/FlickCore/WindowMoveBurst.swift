/// One burst belongs to a single captured window. The mover consumes requests
/// while that window is still held; nothing is replayed against a newly focused
/// window after it has been dropped.
public struct WindowMoveBurst {
    public static let maximumPending = 8
    private var pending: [Direction] = []
    public private(set) var accepting = false
    public var pendingCount: Int { pending.count }

    public init() {}

    public mutating func begin() {
        pending.removeAll()
        accepting = true
    }

    public mutating func enqueue(_ direction: Direction) -> Bool {
        guard accepting, pending.count < Self.maximumPending else { return false }
        pending.append(direction)
        return true
    }

    public mutating func takeNext() -> Direction? {
        guard accepting, !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    /// Close before mouse-up, or on error/cancellation, discarding all
    /// unexecuted requests.
    public mutating func close() {
        accepting = false
        pending.removeAll()
    }
}
