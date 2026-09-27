import CoreGraphics
import Testing
@testable import JustThisCore

/// Feed dodge times to a fresh tracker; return which ones fired the hint.
func fired(_ times: [Double]) -> [Bool] {
    var r = ReachTracker(threshold: 3, window: 4)
    return times.map { r.recordDodge(at: $0) }
}

@Test func hintAfterThreeQuickDodges() {
    #expect(fired([0, 1, 2]) == [false, false, true])
}

@Test func noHintWhenDodgesAreSpreadOut() {
    #expect(fired([0, 3, 7.5]) == [false, false, false]) // first one aged out
}

@Test func hintResetsHistorySoItDoesNotRefireEveryDodge() {
    #expect(fired([0, 1, 2, 2.5]) == [false, false, true, false])
}

let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
let right = CGRect(x: 1000, y: 0, width: 800, height: 600)
let size = CGSize(width: 200, height: 28)

@Test func restsAnywhereOnScreen() {
    let f = placeHome(center: CGPoint(x: 300, y: 150), size: size, screens: [left, right])
    #expect(f == CGRect(x: 200, y: 136, width: 200, height: 28))
}

@Test func restsOnSecondDisplay() {
    let f = placeHome(center: CGPoint(x: 1400, y: 300), size: size, screens: [left, right])
    #expect(right.contains(f))
}

@Test func clampsPartlyOffscreenBackOn() {
    let f = placeHome(center: CGPoint(x: 990, y: 5), size: size, screens: [left, right])
    #expect(left.contains(f))
}

@Test func unpluggedDisplayFallsBackToFirstScreen() {
    let f = placeHome(center: CGPoint(x: 5000, y: 300), size: size, screens: [left])
    #expect(left.contains(f))
}
