import CoreGraphics
import Testing
@testable import JustThisCore

// Screen 1000x800, pill 200x40 near the top centre (AppKit coords: y grows up).
let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
let home = CGRect(x: 400, y: 720, width: 200, height: 40)
let p: CGFloat = 30

@Test func staysHomeWhenCursorFarAway() {
    let f = nextFrame(home: home, current: home, cursor: CGPoint(x: 100, y: 100), visible: screen, proximity: p, bypass: false)
    #expect(f == home)
}

@Test func dodgesDownWhenCursorApproachesFromAbove() {
    let cursor = CGPoint(x: 500, y: 770)
    let f = nextFrame(home: home, current: home, cursor: cursor, visible: screen, proximity: p, bypass: false)
    #expect(f.size == home.size)
    #expect(f.maxY <= home.minY - p)
    #expect(!f.insetBy(dx: -p, dy: -p).contains(cursor))
}

@Test func dodgesDownEvenFromBelowWhenNoRoomAbove() {
    // Cursor just under the pill; there's no room above, so it must jump below the cursor.
    let cursor = CGPoint(x: 500, y: 700)
    let f = nextFrame(home: home, current: home, cursor: cursor, visible: screen, proximity: p, bypass: false)
    #expect(screen.contains(f))
    #expect(!f.insetBy(dx: -p, dy: -p).contains(cursor))
}

@Test func dodgesUpWhenCursorBelowAndRoomAbove() {
    let mid = CGRect(x: 400, y: 400, width: 200, height: 40)
    let cursor = CGPoint(x: 500, y: 390)
    let f = nextFrame(home: mid, current: mid, cursor: cursor, visible: screen, proximity: p, bypass: false)
    #expect(f.minY >= mid.maxY + p)
    #expect(!f.insetBy(dx: -p, dy: -p).contains(cursor))
}

@Test func holdsDodgedSpotWhileCursorLingersNearHome() {
    let dodged = CGRect(x: 400, y: 600, width: 200, height: 40)
    let f = nextFrame(home: home, current: dodged, cursor: CGPoint(x: 500, y: 740), visible: screen, proximity: p, bypass: false)
    #expect(f == dodged)
}

@Test func returnsHomeOnceCursorLeaves() {
    let dodged = CGRect(x: 400, y: 600, width: 200, height: 40)
    let f = nextFrame(home: home, current: dodged, cursor: CGPoint(x: 100, y: 100), visible: screen, proximity: p, bypass: false)
    #expect(f == home)
}

@Test func bypassKeepsItHomeUnderTheCursor() {
    let f = nextFrame(home: home, current: home, cursor: CGPoint(x: 500, y: 740), visible: screen, proximity: p, bypass: true)
    #expect(f == home)
}
