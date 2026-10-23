/// Carbon may repeat pressed events while the bracket key is down. Modifiers
/// can remain held between distinct bracket presses without retriggering a move.
public struct HotKeyPressTracker {
    private var pressed: Set<UInt32> = []
    public init() {}
    public mutating func press(_ id: UInt32) -> Bool { pressed.insert(id).inserted }
    public mutating func release(_ id: UInt32) { pressed.remove(id) }
}
