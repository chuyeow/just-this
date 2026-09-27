import CoreGraphics

/// Where the pill should sit given the cursor. Pure: the shell polls the cursor and animates to the result.
///
/// - Cursor outside the zone around `home` (or `bypass`): go home.
/// - Cursor in the zone, but the current dodged spot is already clear of it: stay put (no jitter).
/// - Otherwise jump vertically away from the cursor, preferring the side opposite it, and
///   flipping sides when that would leave the visible screen. The result always keeps
///   `proximity` of clearance from the cursor.
public func nextFrame(home: CGRect, current: CGRect, cursor: CGPoint, visible: CGRect, proximity: CGFloat, bypass: Bool) -> CGRect {
    let zone = { (r: CGRect) in r.insetBy(dx: -proximity, dy: -proximity) }
    if bypass || !zone(home).contains(cursor) { return home }
    if current != home && !zone(current).contains(cursor) { return current }

    var down = home
    down.origin.y = min(cursor.y, home.minY) - proximity - home.height
    var up = home
    up.origin.y = max(cursor.y, home.maxY) + proximity

    let preferred = cursor.y >= home.midY ? [down, up] : [up, down]
    return preferred.first { visible.contains($0) } ?? preferred[0]
}

/// Notices the user repeatedly reaching for the pill (it keeps dodging) so the shell can
/// suggest holding Option. Fires once per burst, then starts counting afresh.
public struct ReachTracker {
    public var threshold: Int
    public var window: Double
    private var dodges: [Double] = []

    public init(threshold: Int = 3, window: Double = 4) {
        self.threshold = threshold
        self.window = window
    }

    /// Record a dodge at time `t` (seconds). Returns true when the hint should show.
    public mutating func recordDodge(at t: Double) -> Bool {
        dodges = dodges.filter { t - $0 < window } + [t]
        guard dodges.count >= threshold else { return false }
        dodges = []
        return true
    }
}

/// The pill's resting frame: centred on `center`, on the screen that contains it (else the
/// first screen), pulled fully on-screen so a drag or an unplugged display can't lose it.
public func placeHome(center: CGPoint, size: CGSize, screens: [CGRect]) -> CGRect {
    guard let screen = screens.first(where: { $0.contains(center) }) ?? screens.first else {
        return CGRect(origin: center, size: size)
    }
    let x = min(max(center.x - size.width / 2, screen.minX), screen.maxX - size.width)
    let y = min(max(center.y - size.height / 2, screen.minY), screen.maxY - size.height)
    return CGRect(x: x, y: y, width: size.width, height: size.height)
}
