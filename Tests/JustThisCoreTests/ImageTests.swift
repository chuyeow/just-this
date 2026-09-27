import CoreGraphics
import Foundation
import Testing
@testable import JustThisCore

@Test func imageKeepsAspectAtChosenWidth() {
    #expect(ImageSizing.size(natural: CGSize(width: 1600, height: 900), width: 320) == CGSize(width: 320, height: 180))
}

@Test func imageWidthIsClamped() {
    #expect(ImageSizing.size(natural: CGSize(width: 100, height: 100), width: 10).width == ImageSizing.minWidth)
    #expect(ImageSizing.size(natural: CGSize(width: 100, height: 100), width: 5000).width == ImageSizing.maxWidth)
}

@Test func degenerateImageDoesNotDivideByZero() {
    let s = ImageSizing.size(natural: .zero, width: 200)
    #expect(s.width == 200 && s.height.isFinite)
}

@Test func cardWithoutImageIsJustThePill() {
    let l = cardLayout(pill: CGSize(width: 180, height: 28), image: nil, gap: 6)
    #expect(l.size == CGSize(width: 180, height: 28))
    #expect(l.pill == CGRect(x: 0, y: 0, width: 180, height: 28))
    #expect(l.image == nil)
}

@Test func imageSitsUnderThePillBothCentred() {
    // AppKit coords: y grows up, so the pill is at the top.
    let l = cardLayout(pill: CGSize(width: 180, height: 28), image: CGSize(width: 300, height: 200), gap: 6)
    #expect(l.size == CGSize(width: 300, height: 234))
    #expect(l.pill == CGRect(x: 60, y: 206, width: 180, height: 28))
    #expect(l.image == CGRect(x: 0, y: 0, width: 300, height: 200))
}

@Test func narrowImageIsCentredUnderWiderPill() {
    let l = cardLayout(pill: CGSize(width: 300, height: 28), image: CGSize(width: 100, height: 50), gap: 6)
    #expect(l.image == CGRect(x: 100, y: 0, width: 100, height: 50))
}

@Test(arguments: ["https://example.com/cat.png", "  http://example.com/a.jpg\n", "file:///tmp/x.gif"])
func pastedImageURLsAreAccepted(_ s: String) {
    #expect(imageURL(fromPasted: s) != nil)
}

@Test(arguments: ["just some words", "ftp://example.com/a.png", "javascript:alert(1)", "https://", ""])
func otherPastedTextIsNotAnImageURL(_ s: String) {
    #expect(imageURL(fromPasted: s) == nil)
}
