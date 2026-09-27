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
    private var statusItem: NSStatusItem!
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
        buildPanel()
        buildStatusItem()
        applySettings()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
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

    private func buildPanel() {
        panel = PillPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.canHide = false // NSApp.hide after editing returns focus; the pill stays

        let pill = PillView()
        pill.material = .hudWindow
        pill.appearance = NSAppearance(named: .vibrantDark)
        pill.state = .active
        pill.blendingMode = .behindWindow
        pill.wantsLayer = true
        pill.layer?.cornerCurve = .continuous
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pill.menu = menu

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0.62, blue: 0.1, alpha: 1).cgColor
        dot.layer?.cornerRadius = 4
        dot.layer?.shadowColor = dot.layer?.backgroundColor
        dot.layer?.shadowOpacity = 0.9
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOffset = .zero

        field.textColor = .white
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
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "smallcircle.filled.circle", accessibilityDescription: "Just This")
        statusItem.menu = menu
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
        layout()
    }

    /// Size the pill to its text and rest it at the saved spot (default: top centre of the main display).
    /// A dodged pill stays dodged, resized around its own centre.
    private func layout() {
        let font = field.font!
        let text = (field.stringValue as NSString).size(withAttributes: [.font: font])
        let height = ceil(font.pointSize + 15)
        let size = CGSize(width: min(max(text.width + 50, 120), 560), height: height)
        panel.contentView?.layer?.cornerRadius = height / 2

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
        (panel.contentView as? PillView)?.isEditing = true
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
        (panel.contentView as? PillView)?.isEditing = false
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
