import AppKit
import JustThisCore

/// Borderless panel that floats above everything, on every Space, including full-screen apps.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.12 }
}

/// The capsule. Owns clicks (the label never sees them): double-click edits, drag moves.
final class PillView: NSVisualEffectView {
    var onDoubleClick: () -> Void = {}
    var onMoved: () -> Void = {}
    var isEditing = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        isEditing ? super.hitTest(point) : (frame.contains(point) ? self : nil)
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick(); return }
        window?.performDrag(with: event)
        onMoved()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private let defaults: UserDefaults
    private let proximity: CGFloat = 24
    private(set) var panel: PillPanel!
    let field = NSTextField(labelWithString: "")
    private var statusItem: NSStatusItem!
    private var home: CGRect = .zero
    private var editing = false
    private var target: CGRect = .zero
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var focus: String {
        get { defaults.string(forKey: "focus") ?? "Double-click to set your focus" }
        set { defaults.set(newValue, forKey: "focus") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        buildPanel()
        buildStatusItem()
        layout()
        panel.orderFrontRegardless()
        // ponytail: 60 Hz cursor poll; a global mouseMoved monitor is the upgrade if this ever shows in Activity Monitor.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: UI

    private func buildPanel() {
        panel = PillPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let pill = PillView()
        pill.material = .hudWindow
        pill.appearance = NSAppearance(named: .vibrantDark)
        pill.state = .active
        pill.blendingMode = .behindWindow
        pill.wantsLayer = true
        pill.layer?.cornerCurve = .continuous
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0.62, blue: 0.1, alpha: 1).cgColor
        dot.layer?.cornerRadius = 4
        dot.layer?.shadowColor = dot.layer?.backgroundColor
        dot.layer?.shadowOpacity = 0.9
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOffset = .zero

        field.font = NSFont(descriptor: NSFont.systemFont(ofSize: 13, weight: .medium).fontDescriptor.withDesign(.rounded)!, size: 13)
        field.textColor = .white
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .none
        field.delegate = self
        field.stringValue = focus
        field.toolTip = "Double-click to edit · hold ⌥ to stop it dodging · ⌥-drag to move"

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
        let menu = NSMenu()
        menu.addItem(withTitle: "Edit Focus…", action: #selector(beginEditing), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Reset Position", action: #selector(resetPosition), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Just This", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// Size the pill to its text and anchor it at the saved spot (default: top centre under the menu bar).
    private func layout() {
        guard let screen = NSScreen.main else { return }
        let text = (field.stringValue as NSString).size(withAttributes: [.font: field.font!])
        let size = CGSize(width: min(max(text.width + 50, 120), 480), height: 28)
        panel.contentView?.layer?.cornerRadius = size.height / 2
        let vf = screen.visibleFrame
        let center = defaults.object(forKey: "homeX") != nil
            ? CGPoint(x: defaults.double(forKey: "homeX"), y: defaults.double(forKey: "homeY"))
            : CGPoint(x: vf.midX, y: vf.maxY - 10 - size.height / 2)
        home = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        target = home
        panel.setFrame(home, display: true)
    }

    // MARK: Dodge loop

    private func tick() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        let next = nextFrame(home: home, current: target, cursor: NSEvent.mouseLocation, visible: screen.visibleFrame,
                             proximity: proximity, bypass: editing || optionHeld)
        guard next != target else { return }
        target = next
        panel.setFrame(next, display: true, animate: true)
    }

    // MARK: Editing

    /// Called after a drag; the drop spot becomes the new home.
    private func saveHome() {
        guard panel.frame != home else { return }
        home = panel.frame
        target = home
        defaults.set(home.midX, forKey: "homeX")
        defaults.set(home.midY, forKey: "homeY")
    }

    @objc func beginEditing() {
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

    @objc private func resetPosition() {
        defaults.removeObject(forKey: "homeX")
        defaults.removeObject(forKey: "homeY")
        layout()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
