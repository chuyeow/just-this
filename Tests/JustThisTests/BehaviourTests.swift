import AppKit
import Testing
@testable import JustThis
import JustThisCore

/// Drives the real shell's tick with a fake cursor/clock, and settings through UserDefaults.
@MainActor
struct BehaviourTests {
    let defaults = UserDefaults(suiteName: "JustThisTests-\(UUID())")!
    let app = { let a = NSApplication.shared; a.setActivationPolicy(.accessory); return a }()

    func launch() -> AppDelegate {
        defaults.set("Write the memo", forKey: Setting.focus)
        let d = AppDelegate(defaults: defaults)
        d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return d
    }

    var far: CGPoint { CGPoint(x: 5, y: 5) }

    @Test func dodgesThenReturns() {
        let d = launch()
        let home = d.panel.frame
        d.tick(cursor: CGPoint(x: home.midX, y: home.midY), optionHeld: false, now: 0)
        #expect(d.panel.frame != home)
        d.tick(cursor: far, optionHeld: false, now: 0.5)
        #expect(d.panel.frame == home)
    }

    @Test func dodgeCanBeTurnedOff() {
        let d = launch()
        defaults.set(false, forKey: Setting.dodgeEnabled)
        let home = d.panel.frame
        d.tick(cursor: CGPoint(x: home.midX, y: home.midY), optionHeld: false, now: 0)
        #expect(d.panel.frame == home)
    }

    @Test func showsHoldOptionHintWhenUserKeepsReaching() {
        let d = launch()
        let home = d.panel.frame
        for t in [0.0, 1, 2] {
            d.tick(cursor: CGPoint(x: home.midX, y: home.midY), optionHeld: false, now: t)
            d.tick(cursor: far, optionHeld: false, now: t + 0.5)
        }
        #expect(d.field.stringValue == AppDelegate.reachHint)
        // Holding Option answers the hint: back to the focus, and the pill stays put under the cursor.
        d.tick(cursor: CGPoint(x: home.midX, y: home.midY), optionHeld: true, now: 3)
        #expect(d.field.stringValue == "Write the memo")
    }

    @Test func hintCanBeTurnedOff() {
        let d = launch()
        defaults.set(false, forKey: Setting.showReachHint)
        let home = d.panel.frame
        for t in [0.0, 1, 2] {
            d.tick(cursor: CGPoint(x: home.midX, y: home.midY), optionHeld: false, now: t)
            d.tick(cursor: far, optionHeld: false, now: t + 0.5)
        }
        #expect(d.field.stringValue == "Write the memo")
    }

    @Test func textSizeAndOpacityApplyLive() {
        let d = launch()
        let before = d.panel.frame
        defaults.set(18.0, forKey: Setting.fontSize)
        defaults.set(0.6, forKey: Setting.opacity)
        #expect(d.panel.frame.height > before.height)
        #expect(d.panel.frame.width > before.width)
        #expect(abs(d.panel.alphaValue - 0.6) < 0.01)
    }

    @Test func dodgeDistanceApplies() {
        let d = launch()
        defaults.set(80.0, forKey: Setting.dodgeDistance)
        let home = d.panel.frame
        // 60pt below the pill: outside the default 24pt zone, inside an 80pt one.
        d.tick(cursor: CGPoint(x: home.midX, y: home.minY - 60), optionHeld: false, now: 0)
        #expect(d.panel.frame != home)
    }

    @Test func settingsWindowOpens() {
        let d = launch()
        d.openSettings()
        #expect(d.settingsWindow?.isVisible == true)
        #expect(d.settingsWindow?.title == "Just This Settings")
    }
}

@MainActor
struct DockThemeBreathTests {
    let defaults = UserDefaults(suiteName: "JustThisTests-\(UUID())")!
    let app = NSApplication.shared

    func launch() -> AppDelegate {
        let d = AppDelegate(defaults: defaults)
        d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return d
    }

    @Test func dockMenuOffersEditAndSettings() {
        let d = launch()
        let titles = d.applicationDockMenu(app)?.items.map(\.title) ?? []
        #expect(titles.contains("Edit Focus…"))
        #expect(titles.contains("Settings…"))
    }

    @Test func clickingDockIconStartsEditing() {
        let d = launch()
        _ = d.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        #expect(d.field.isEditable)
    }

    @Test func mainMenuSupportsPasteWhileEditing() {
        _ = launch()
        let actions = app.mainMenu?.items.flatMap { $0.submenu?.items ?? [] }.compactMap(\.action) ?? []
        #expect(actions.contains(#selector(NSText.paste(_:))))
        #expect(actions.contains(#selector(NSApplication.terminate(_:))))
    }

    @Test func themeAppliesLive() {
        let d = launch()
        defaults.set("paper", forKey: Setting.theme)
        let paper = Themes.named("paper")
        #expect(d.field.textColor == NSColor(paper.text))
        #expect(d.pill.appearance?.name == .vibrantLight)
    }

    @Test func breathesUnlessTurnedOff() {
        let d = launch()
        #expect(d.dot.layer?.animation(forKey: "breathe") != nil)
        defaults.set(false, forKey: Setting.breathe)
        #expect(d.dot.layer?.animation(forKey: "breathe") == nil)
    }
}
