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
        let d = AppDelegate(defaults: defaults, storage: scratchStorage())
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

    @Test func noPollingWhileRestingAtHome() {
        let d = launch()
        #expect(!d.isPolling) // idle: no timer, only mouse-moved events wake us
        let home = d.panel.frame
        d.tick(cursor: CGPoint(x: home.midX, y: home.midY), optionHeld: false, now: 0)
        #expect(d.isPolling) // dodged: watch for ⌥ (no event for it without extra permissions)
        d.tick(cursor: far, optionHeld: false, now: 0.5)
        #expect(!d.isPolling) // home again: back to idle
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

    func launch(reduceMotion: Bool = false) -> AppDelegate {
        let d = AppDelegate(defaults: defaults, storage: scratchStorage())
        d.reduceMotion = { reduceMotion }
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
        #expect(actions.contains(#selector(NSWindow.performClose(_:)))) // ⌘W closes Settings
    }

    @Test func freshInstallUsesDawnGradient() {
        let d = launch()
        let dawn = Themes.named("dawn")
        #expect(d.field.textColor == NSColor(dawn.text))
        #expect(d.pill.appearance?.name == .vibrantLight)
        let colors = (d.tint.layer as? CAGradientLayer)?.colors as? [CGColor] ?? []
        #expect(colors.count == 2 && colors[0] != colors[1])
    }

    @Test func themeAppliesLive() {
        let d = launch()
        defaults.set("ocean", forKey: Setting.theme)
        #expect(d.field.textColor == NSColor(Themes.named("ocean").text))
        #expect(d.pill.appearance?.name == .vibrantDark)
    }

    @Test func breathesUnlessTurnedOff() {
        let d = launch()
        #expect(d.dot.layer?.animation(forKey: "breathe") != nil)
        // The whole pill breathes: it swells gently (scale) and brightens (opacity), not just the dot.
        let whole = d.pill.layer?.animation(forKey: "breathe") as? CAAnimationGroup
        let keys = whole?.animations?.compactMap { ($0 as? CAPropertyAnimation)?.keyPath } ?? []
        #expect(keys.contains("transform"))
        #expect(keys.contains("opacity"))
        defaults.set(false, forKey: Setting.breathe)
        #expect(d.dot.layer?.animation(forKey: "breathe") == nil)
        #expect(d.pill.layer?.animation(forKey: "breathe") == nil)
    }

    @Test func reduceMotionStopsBreathing() {
        let d = launch(reduceMotion: true)
        #expect(d.dot.layer?.animation(forKey: "breathe") == nil)
        #expect(d.pill.layer?.animation(forKey: "breathe") == nil)
    }
}

@MainActor
struct DragAndShortcutTests {
    let defaults = UserDefaults(suiteName: "JustThisTests-\(UUID())")!
    let app = { let a = NSApplication.shared; a.setActivationPolicy(.accessory); return a }()

    func launch() -> AppDelegate {
        let d = AppDelegate(defaults: defaults, storage: scratchStorage())
        d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return d
    }

    /// Mouse event at a screen point, expressed in the panel's current window coordinates.
    func mouse(_ type: NSEvent.EventType, _ d: AppDelegate, at screen: CGPoint, clicks: Int = 1) -> NSEvent {
        let o = d.panel.frame.origin
        return NSEvent.mouseEvent(with: type, location: CGPoint(x: screen.x - o.x, y: screen.y - o.y), modifierFlags: .option,
                                  timestamp: 0, windowNumber: d.panel.windowNumber, context: nil, eventNumber: 0,
                                  clickCount: clicks, pressure: 1)!
    }

    @Test func dragRestsExactlyWhereDropped() {
        let d = launch()
        let start = CGPoint(x: d.panel.frame.midX, y: d.panel.frame.midY)
        let screen = NSScreen.main!.frame
        let drop = CGPoint(x: screen.midX - 150, y: screen.midY - 100)
        d.pill.mouseDown(with: mouse(.leftMouseDown, d, at: start))
        for i in 1...10 {
            let t = CGFloat(i) / 10
            let p = CGPoint(x: start.x + (drop.x - start.x) * t, y: start.y + (drop.y - start.y) * t)
            d.pill.mouseDragged(with: mouse(.leftMouseDragged, d, at: p))
            // The dodge loop must not fight the drag, even with Option released mid-drag.
            d.tick(cursor: p, optionHeld: false, now: Double(i))
        }
        d.pill.mouseUp(with: mouse(.leftMouseUp, d, at: drop))
        #expect(abs(d.panel.frame.midX - drop.x) < 1)
        #expect(abs(d.panel.frame.midY - drop.y) < 1, "frame \(d.panel.frame) drop \(drop) start \(start)")
        let saved = defaults.array(forKey: Setting.home) as? [Double] ?? []
        #expect(saved.count == 2 && abs(saved[0] - drop.x) < 1 && abs(saved[1] - drop.y) < 1)
        // And it stays there once the cursor leaves.
        d.tick(cursor: CGPoint(x: 5, y: 5), optionHeld: false, now: 20)
        #expect(abs(d.panel.frame.midX - drop.x) < 1)
    }

    @Test func clickAsksToActivateButNeverSilentlyTakesKeyboard() {
        let d = launch()
        let c = CGPoint(x: d.panel.frame.midX, y: d.panel.frame.midY)
        d.pill.mouseDown(with: mouse(.leftMouseDown, d, at: c))
        d.pill.mouseUp(with: mouse(.leftMouseUp, d, at: c))
        #expect(d.wantsKeyOnActivate)
        // Keyboard focus only moves once the app is actually active.
        d.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))
        #expect(!d.wantsKeyOnActivate)
    }

    @Test func draggingDoesNotAskForFocus() {
        let d = launch()
        let c = CGPoint(x: d.panel.frame.midX, y: d.panel.frame.midY)
        d.pill.mouseDown(with: mouse(.leftMouseDown, d, at: c))
        d.pill.mouseDragged(with: mouse(.leftMouseDragged, d, at: CGPoint(x: c.x - 40, y: c.y - 40)))
        d.pill.mouseUp(with: mouse(.leftMouseUp, d, at: CGPoint(x: c.x - 40, y: c.y - 40)))
        #expect(!d.wantsKeyOnActivate)
    }

    @Test func commandCommaOnThePillOpensSettings() {
        let d = launch()
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                 windowNumber: d.panel.windowNumber, context: nil, characters: ",",
                                 charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)!
        #expect(d.panel.performKeyEquivalent(with: e))
        #expect(d.settingsWindow?.isVisible == true)
    }

}
