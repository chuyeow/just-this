import Testing
@testable import JustThisCore

@Test(arguments: Themes.all)
func textIsReadable(_ t: Theme) {
    #expect(contrastRatio(t.text, t.background) >= 4.5, "\(t.name) text")
}

@Test(arguments: Themes.all)
func dotStandsOut(_ t: Theme) {
    #expect(contrastRatio(t.accent, t.background) >= 3, "\(t.name) dot")
}

@Test func themeIdsAreUnique() {
    #expect(Set(Themes.all.map(\.id)).count == Themes.all.count)
}

@Test func unknownThemeFallsBackToDefault() {
    #expect(Themes.named("nope").id == Themes.all[0].id)
    #expect(Themes.named(nil).id == Themes.all[0].id)
    #expect(Themes.named("paper").id == "paper")
}

@Test func contrastMatchesWCAGReference() {
    #expect(abs(contrastRatio(RGB(hex: 0x000000), RGB(hex: 0xFFFFFF)) - 21) < 0.01)
    #expect(abs(contrastRatio(RGB(hex: 0x777777), RGB(hex: 0xFFFFFF)) - 4.48) < 0.01)
}
