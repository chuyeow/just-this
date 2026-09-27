import AppKit
import JustThisCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    static let reachHint = "Hold ⌥ Option key to reach"

    private let defaults: UserDefaults
    private(set) var panel: PillPanel!
    private(set) var settingsWindow: NSWindow?
    let field = NSTextField(labelWithString: "")
    let pill = PillView()
    let dot = NSView()
    private let tint = NSView()
    private let menu = NSMenu()
    private var home: CGRect = .zero
    private var target: CGRect = .zero
    private var editing = false
    private var reach = ReachTracker()
    private var hintShownAt: Double?
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Setting.defaults)
    }

    var focus: String {
        get { defaults.string(forKey: Setting.focus) ?? "Double-click to set your focus" }
        set { defaults.set(newValue, forKey: Setting.focus) }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        buildMainMenu()
        buildPanel()
        applySettings()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        // ponytail: 60 Hz cursor poll; a global mouseMoved monitor is the upgrade if this ever shows in Activity Monitor.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick(cursor: NSEvent.mouseLocation, optionHeld: NSEvent.modifierFlags.contains(.option),
                           now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    // MARK: UI

    private func buildMenu() {
        menu.addItem(withTitle: "Edit Focus…", action: #selector(beginEditing), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Just This", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// The menu bar menus shown while the app is active. Edit is what makes ⌘C/⌘V/⌘A work in the field.
    private func buildMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Just This", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Just This", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Edit Focus…", action: #selector(beginEditing), keyEquivalent: "e").target = self
        edit.addItem(.separator())
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for sub in [appMenu, edit] {
            let item = NSMenuItem()
            item.submenu = sub
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dock = NSMenu()
        dock.addItem(withTitle: "Edit Focus…", action: #selector(beginEditing), keyEquivalent: "").target = self
        dock.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        return dock
    }

    /// Clicking the Dock icon goes straight to changing the focus.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        beginEditing()
        return false
    }

    private func buildPanel() {
        panel = PillPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.canHide = false // NSApp.hide after editing returns focus; the pill stays

        pill.material = .hudWindow
        pill.state = .active
        pill.blendingMode = .behindWindow
        pill.wantsLayer = true
        pill.layer?.cornerCurve = .continuous
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 1
        pill.menu = menu

        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        pill.addSubview(tint)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.shadowOpacity = 0.9
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOffset = .zero

        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .none
        field.delegate = self
        field.stringValue = focus
        field.toolTip = "Double-click to edit · hold ⌥ to reach it · ⌥-drag to move · right-click for menu"

        for v in [dot, field] { v.translatesAutoresizingMaskIntoConstraints = false; pill.addSubview(v) }
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
            field.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        pill.onDoubleClick = { [weak self] in self?.beginEditing() }
        pill.onMoved = { [weak self] in self?.saveHome() }
        panel.contentView = pill
        tint.frame = pill.bounds
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView:
                SettingsView(resetPosition: { [weak self] in self?.resetPosition() }).defaultAppStorage(defaults)))
            w.title = "Just This Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func applySettings() {
        let size = defaults.double(forKey: Setting.fontSize)
        field.font = NSFont(descriptor: NSFont.systemFont(ofSize: size, weight: .medium).fontDescriptor.withDesign(.rounded)!, size: size)
        panel.alphaValue = defaults.double(forKey: Setting.opacity)
        applyTheme(Themes.named(defaults.string(forKey: Setting.theme)))
        layout()
    }

    private func applyTheme(_ t: Theme) {
        pill.appearance = NSAppearance(named: t.isDark ? .vibrantDark : .vibrantLight)
        tint.layer?.backgroundColor = NSColor(t.background).withAlphaComponent(0.82).cgColor
        field.textColor = NSColor(t.text)
        let accent = NSColor(t.accent).cgColor
        dot.layer?.backgroundColor = accent
        dot.layer?.shadowColor = accent
        pill.layer?.borderColor = NSColor(t.accent).withAlphaComponent(0.15).cgColor
    }

    /// A slow inhale/exhale, ~10 breaths a minute. The whole pill swells a touch and brightens,
    /// the dot's glow blooms and the rim warms. Scale never exceeds 1 so the window never clips it.
    /// Re-run after every layout: the scale pivots on the pill's centre, which moves with its size.
    private func updateBreathing() {
        stopBreathing()
        guard defaults.bool(forKey: Setting.breathe), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let accent = NSColor(Themes.named(defaults.string(forKey: Setting.theme)).accent)
        func wave(_ key: String, _ from: Any, _ to: Any) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            return a
        }
        let b = pill.bounds
        var exhale = CATransform3DMakeTranslation(b.midX, b.midY, 0)
        exhale = CATransform3DScale(exhale, 0.965, 0.965, 1)
        exhale = CATransform3DTranslate(exhale, -b.midX, -b.midY, 0)

        let dotBreath = CAAnimationGroup()
        dotBreath.animations = [wave("opacity", 0.55, 1.0), wave("shadowRadius", 1.0, 8.0), wave("shadowOpacity", 0.4, 1.0)]
        let pillBreath = CAAnimationGroup()
        pillBreath.animations = [
            wave("transform", NSValue(caTransform3D: exhale), NSValue(caTransform3D: CATransform3DIdentity)),
            wave("opacity", 0.8, 1.0),
            wave("borderColor", accent.withAlphaComponent(0.08).cgColor, accent.withAlphaComponent(0.5).cgColor),
        ]
        for (layer, anim) in [(dot.layer, dotBreath), (pill.layer, pillBreath)] {
            anim.duration = 3
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.isRemovedOnCompletion = false
            layer?.add(anim, forKey: "breathe")
        }
    }

    private func stopBreathing() {
        dot.layer?.removeAnimation(forKey: "breathe")
        pill.layer?.removeAnimation(forKey: "breathe")
    }

    /// Size the pill to its text and rest it at the saved spot (default: top centre of the main display).
    /// A dodged pill stays dodged, resized around its own centre.
    private func layout() {
        let font = field.font!
        let text = (field.stringValue as NSString).size(withAttributes: [.font: font])
        let height = ceil(font.pointSize + 15)
        let size = CGSize(width: min(max(text.width + 50, 120), 560), height: height)
        pill.layer?.cornerRadius = height / 2

        let wasDodged = target != home
        let screens = NSScreen.screens.map(\.frame)
        let center: CGPoint
        if defaults.object(forKey: Setting.homeX) != nil {
            center = CGPoint(x: defaults.double(forKey: Setting.homeX), y: defaults.double(forKey: Setting.homeY))
        } else {
            let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            center = CGPoint(x: vf.midX, y: vf.maxY - 10 - height / 2)
        }
        home = placeHome(center: center, size: size, screens: screens)
        target = wasDodged ? placeHome(center: CGPoint(x: target.midX, y: target.midY), size: size, screens: screens) : home
        panel.setFrame(target, display: true)
        pill.layoutSubtreeIfNeeded()
        updateBreathing()
    }

    // MARK: Dodge loop

    func tick(cursor: CGPoint, optionHeld: Bool, now: Double) {
        if let shown = hintShownAt, optionHeld || now - shown > 3 { hideHint() }

        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: home.midX, y: home.midY)) } ?? NSScreen.main
        guard let screen else { return }
        let bypass = editing || optionHeld || !defaults.bool(forKey: Setting.dodgeEnabled)
        let next = nextFrame(home: home, current: target, cursor: cursor, visible: screen.frame,
                             proximity: defaults.double(forKey: Setting.dodgeDistance), bypass: bypass)
        guard next != target else { return }
        target = next
        panel.setFrame(next, display: true, animate: true)

        if next != home, reach.recordDodge(at: now), defaults.bool(forKey: Setting.showReachHint) {
            showHint(at: now)
        }
    }

    private func showHint(at now: Double) {
        hintShownAt = now
        field.stringValue = Self.reachHint
        layout()
    }

    private func hideHint() {
        hintShownAt = nil
        field.stringValue = focus
        layout()
    }

    // MARK: Editing

    /// Called after a drag; the drop spot becomes the new home.
    private func saveHome() {
        guard panel.frame != home else { return }
        home = panel.frame
        target = home
        defaults.set(home.midX, forKey: Setting.homeX)
        defaults.set(home.midY, forKey: Setting.homeY)
    }

    @objc func beginEditing() {
        if hintShownAt != nil { hideHint() }
        editing = true
        pill.isEditing = true
        field.isEditable = true
        field.isSelectable = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func endEditing(commit: Bool) {
        guard editing else { return }
        editing = false
        pill.isEditing = false
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit && !text.isEmpty { focus = text }
        field.stringValue = focus
        field.isEditable = false
        field.isSelectable = false
        panel.makeFirstResponder(nil)
        layout()
        NSApp.hide(nil) // hand focus back to whatever the user was in
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): endEditing(commit: true); return true
        case #selector(NSResponder.cancelOperation(_:)): endEditing(commit: false); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ note: Notification) { endEditing(commit: true) }

    private func resetPosition() {
        defaults.removeObject(forKey: Setting.homeX)
        defaults.removeObject(forKey: Setting.homeY)
        layout()
    }
}
