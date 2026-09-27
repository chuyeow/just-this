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
