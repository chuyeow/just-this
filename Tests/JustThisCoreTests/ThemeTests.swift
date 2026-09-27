import Testing
@testable import JustThisCore

/// Gradient themes must be readable at both ends.
@Test(arguments: Themes.all)
func textIsReadable(_ t: Theme) {
    for bg in [t.background, t.backgroundEnd ?? t.background] {
        #expect(contrastRatio(t.text, bg) >= 4.5, "\(t.name) text")
    }
}

@Test(arguments: Themes.all)
func dotStandsOut(_ t: Theme) {
    for bg in [t.background, t.backgroundEnd ?? t.background] {
        #expect(contrastRatio(t.accent, bg) >= 3, "\(t.name) dot")
    }
}

@Test func themeLineup() {
    #expect(Themes.all.map(\.id) == ["dawn", "paper", "ember", "ocean", "forest", "gold"])
    #expect(Themes.named("dawn").backgroundEnd != nil)
}

@Test func themeIdsAreUnique() {
    #expect(Set(Themes.all.map(\.id)).count == Themes.all.count)
}

@Test func unknownThemeFallsBackToDefault() {
    #expect(Themes.named("nope").id == Themes.all[0].id)
    #expect(Themes.named(nil).id == Themes.all[0].id)
    #expect(Themes.named("ocean").id == "ocean")
}

@Test func contrastMatchesWCAGReference() {
    #expect(abs(contrastRatio(RGB(hex: 0x000000), RGB(hex: 0xFFFFFF)) - 21) < 0.01)
    #expect(abs(contrastRatio(RGB(hex: 0x777777), RGB(hex: 0xFFFFFF)) - 4.48) < 0.01)
}

@Test func dawnIsTheDefault() {
    #expect(Themes.default.id == "dawn")
    #expect(Themes.named(nil).id == "dawn")
    #expect(Themes.named("rose").id == "dawn") // removed themes fall back
}
