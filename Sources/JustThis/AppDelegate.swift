import AppKit
import JustThisCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    static let reachHint = "Hold ⌥ Option key to reach"

    private let defaults: UserDefaults
    private(set) var panel: PillPanel!
    private(set) var settingsWindow: NSWindow?
    let field = NSTextField(labelWithString: "")
    let pill = PillView()
    let dot = NSView()
    let tint = NSView()
    let card = CardView()
    let imageView = ImageCardView()
    /// Where ⌘V reads from. Injected in tests so they never touch the real clipboard.
    var pasteboard: NSPasteboard = .general
    private let store: ImageStore
    private var image: NSImage?
    /// During a corner drag: the width being shown, and the card's top-left kept fixed.
    private var liveImageWidth: CGFloat?
    private var resizeAnchor: CGPoint?
    /// Drag pasteboard change count when no mouse button was down; a change while the button is
    /// down means something (like a file) is being dragged, so the card holds still to be dropped on.
    private var idleDragCount = NSPasteboard(name: .drag).changeCount
    private var ignoreDefaultsChanges = false
    /// A click on the card asked macOS to activate us; take keyboard focus once it does. Taking key
    /// without activation would leave the pill silently eating keystrokes meant for the front app.
    private(set) var wantsKeyOnActivate = false
    private let menu = NSMenu()
    private var home: CGRect = .zero
    private var target: CGRect = .zero
    private var editing = false
    private var reach = ReachTracker()
    private var hintShownAt: Double?
    private var timer: Timer?
    private var monitors: [Any] = []
    /// True while the ⌥/hint poll runs: only when the card is away from home or showing a message.
    var isPolling: Bool { timer != nil }

    /// Injected so tests don't depend on the machine's Reduce Motion setting (CI runners have it on).
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(defaults: UserDefaults = .standard, storage: URL = ImageStore.standard) {
        self.defaults = defaults
        self.store = ImageStore(directory: storage)
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
        image = store.load().flatMap(NSImage.init(data:))
        quietly { defaults.set(image != nil, forKey: Setting.hasImage) }
        applySettings()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.ignoreDefaultsChanges else { return }
                self.applySettings()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        // Event-driven: the dodge only runs when the mouse moves (here or in any other app). Global
        // mouse monitors need no permission; key/modifier monitors would, hence the ⌥ poll below.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.sample() }
            return event
        }) { monitors.append(local) }
    }

    // MARK: UI

    private func buildMenu() {
        menu.addItem(withTitle: "Edit Focus…", action: #selector(beginEditing), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Paste Image", action: #selector(pasteFromClipboard), keyEquivalent: "v").target = self
        menu.addItem(withTitle: "Remove Image", action: #selector(removeImage), keyEquivalent: "").target = self
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
        edit.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "v").target = self
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = window
        for sub in [appMenu, edit, window] {
            let item = NSMenuItem()
            item.submenu = sub
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    /// Clicking the card works like clicking any app's window: activate, then the pill is key so
    /// ⌘, and ⌘V reach it. Dragging doesn't activate.
    private func requestFocus() {
        wantsKeyOnActivate = true
        NSApp.activate()
    }

    func applicationDidBecomeActive(_ note: Notification) {
        guard wantsKeyOnActivate else { return }
        wantsKeyOnActivate = false
        panel.makeKey()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dock = NSMenu()
        dock.addItem(withTitle: "Edit Focus…", action: #selector(beginEditing), keyEquivalent: "").target = self
        dock.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        dock.addItem(withTitle: "Paste Image", action: #selector(pasteFromClipboard), keyEquivalent: "").target = self
        if image != nil { dock.addItem(withTitle: "Remove Image", action: #selector(removeImage), keyEquivalent: "").target = self }
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

        tint.layer = CAGradientLayer()
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
        pill.onClick = { [weak self] in self?.requestFocus() }
        panel.onSettingsShortcut = { [weak self] in self?.openSettings() }
        panel.onPaste = { [weak self] editingText in self?.handlePaste(editingText: editingText) ?? false }

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.isEditable = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.menu = menu
        imageView.isHidden = true
        imageView.onMoved = { [weak self] in self?.saveHome() }
        imageView.onClick = { [weak self] in self?.requestFocus() }
        imageView.onResize = { [weak self] width, done in self?.resizeImage(to: width, done: done) }

        card.onDrop = { [weak self] board in Task { await self?.pasteImage(from: board) } }
        card.addSubview(pill)
        card.addSubview(imageView)
        panel.contentView = card
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView:
                SettingsView(resetPosition: { [weak self] in self?.resetPosition() },
                         removeImage: { [weak self] in self?.removeImage() }).defaultAppStorage(defaults)))
            w.title = "Just This Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless() // visible even if macOS declines to activate us
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
        if let gradient = tint.layer as? CAGradientLayer {
            gradient.colors = [t.background, t.backgroundEnd ?? t.background].map { NSColor($0).withAlphaComponent(0.82).cgColor }
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
        }
        field.textColor = NSColor(t.text)
        let accent = NSColor(t.accent).cgColor
        dot.layer?.backgroundColor = accent
        dot.layer?.shadowColor = accent
        pill.layer?.borderColor = NSColor(t.accent).withAlphaComponent(0.15).cgColor
        imageView.layer?.borderColor = NSColor(t.accent).withAlphaComponent(0.35).cgColor
    }

    /// A slow inhale/exhale, ~10 breaths a minute. The whole pill swells a touch and brightens,
    /// the dot's glow blooms and the rim warms. Scale never exceeds 1 so the window never clips it.
    /// Re-run after every layout: the scale pivots on the pill's centre, which moves with its size.
    private func updateBreathing() {
        stopBreathing()
        guard defaults.bool(forKey: Setting.breathe), !reduceMotion() else { return }
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

    /// Size the pill to its text, put the image (if any) under it, and rest the card at the saved
    /// spot (default: top centre of the main display). A dodged card stays dodged, resized around
    /// its own centre; a card being corner-resized keeps its top-left.
    private func layout() {
        let font = field.font!
        let text = (field.stringValue as NSString).size(withAttributes: [.font: font])
        let height = ceil(font.pointSize + 15)
        let pillSize = CGSize(width: min(max(text.width + 50, 120), 560), height: height)
        pill.layer?.cornerRadius = height / 2

        let width: CGFloat = liveImageWidth ?? CGFloat(defaults.double(forKey: Setting.imageWidth))
        let imageSize = image.map { ImageSizing.size(natural: $0.size, width: width) }
        let card = cardLayout(pill: pillSize, image: imageSize, gap: 6)
        pill.frame = card.pill
        tint.frame = pill.bounds
        imageView.image = image
        imageView.isHidden = card.image == nil
        imageView.frame = card.image ?? .zero
        let size = card.size

        let screens = NSScreen.screens.map(\.frame)
        if let anchor = resizeAnchor {
            home = CGRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
            target = home
        } else {
            let wasDodged = target != home
            let center: CGPoint
            if let saved = defaults.array(forKey: Setting.home) as? [Double], saved.count == 2 {
                center = CGPoint(x: saved[0], y: saved[1])
            } else {
                let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
                center = CGPoint(x: vf.midX, y: vf.maxY - 10 - size.height / 2)
            }
            home = placeHome(center: center, size: size, screens: screens)
            target = wasDodged ? placeHome(center: CGPoint(x: target.midX, y: target.midY), size: size, screens: screens) : home
        }
        panel.setFrame(target, display: true)
        pill.layoutSubtreeIfNeeded()
        imageView.window?.invalidateCursorRects(for: imageView)
        updateBreathing()
    }

    // MARK: Image

    @objc func pasteFromClipboard() {
        Task { await pasteImage(from: pasteboard) }
    }

    /// ⌘V: outside the text field it always means "paste an image". While editing the focus text,
    /// an image-only clipboard (image data or a copied image file) still pastes the image; anything
    /// with plain text is left to the field.
    func handlePaste(editingText: Bool) -> Bool {
        guard !editingText || clipboardHoldsOnlyImage(pasteboard) else { return false }
        pasteFromClipboard()
        return true
    }

    /// Edit › Paste: same decision as ⌘V, falling back to the text field's own paste.
    @objc func paste(_ sender: Any?) {
        let editingText = panel.firstResponder is NSText
        if !handlePaste(editingText: editingText), editingText {
            (panel.firstResponder as? NSText)?.paste(sender)
        }
    }

    private func clipboardHoldsOnlyImage(_ board: NSPasteboard) -> Bool {
        if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let file = files.first {
            return UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true
        }
        let hasImage = board.availableType(from: [.png, .tiff, .init("public.jpeg"), .init("com.compuserve.gif"), .init("public.heic")]) != nil
        return hasImage && board.string(forType: .string) == nil
    }

    /// Paste or drop: a copied/dragged image file, raw image data, or text that is an image URL
    /// (downloaded). Returns whether an image was set.
    @discardableResult
    func pasteImage(from board: NSPasteboard) async -> Bool {
        guard let data = await imageData(from: board), setImage(data) else {
            showMessage("That’s not an image I can show")
            return false
        }
        return true
    }

    private func imageData(from board: NSPasteboard) async -> Data? {
        // File URLs first: Finder also puts the file's icon on the pasteboard as image data.
        if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let file = files.first {
            return try? Data(contentsOf: file)
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("com.compuserve.gif"), .init("public.heic")]
        for type in imageTypes {
            if let data = board.data(forType: type) { return data }
        }
        guard let text = board.string(forType: .string) ?? board.string(forType: .URL),
              let url = imageURL(fromPasted: text) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // ponytail: whole-body download capped after the fact; stream with a byte limit if huge URLs become a problem.
        guard let (data, _) = try? await URLSession.shared.data(for: request), data.count <= 25_000_000 else { return nil }
        return data
    }

    private func setImage(_ data: Data) -> Bool {
        guard let new = NSImage(data: data), new.isValid, new.size.width > 0, new.size.height > 0 else { return false }
        do { try store.save(data) } catch { return false }
        image = new
        quietly { defaults.set(true, forKey: Setting.hasImage) }
        layout()
        return true
    }

    @objc func removeImage() {
        store.remove()
        image = nil
        quietly { defaults.set(false, forKey: Setting.hasImage) }
        layout()
    }

    /// Live corner drag: grow/shrink from the fixed top-left; on release, save width and spot together.
    private func resizeImage(to width: CGFloat, done: Bool) {
        if resizeAnchor == nil { resizeAnchor = CGPoint(x: panel.frame.minX, y: panel.frame.maxY) }
        liveImageWidth = min(max(width, ImageSizing.minWidth), ImageSizing.maxWidth)
        layout()
        guard done else { return }
        quietly {
            defaults.set(Double(liveImageWidth!), forKey: Setting.imageWidth)
            defaults.set([panel.frame.midX, panel.frame.midY], forKey: Setting.home)
        }
        liveImageWidth = nil
        resizeAnchor = nil
        layout()
    }

    /// Write several defaults without the change observer laying out between writes.
    private func quietly(_ writes: () -> Void) {
        ignoreDefaultsChanges = true
        writes()
        ignoreDefaultsChanges = false
    }

    // MARK: Dodge loop

    /// Read the live cursor, modifier and drag state and run the dodge once.
    private func sample() {
        let dragCount = NSPasteboard(name: .drag).changeCount
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        if !buttonDown { idleDragCount = dragCount }
        tick(cursor: NSEvent.mouseLocation, optionHeld: NSEvent.modifierFlags.contains(.option),
             fileDragging: buttonDown && dragCount != idleDragCount, now: ProcessInfo.processInfo.systemUptime)
    }

    /// Pressing ⌥ or a message timing out produce no mouse event, so poll (10 Hz) only while one of
    /// those can matter: the card is dodged, or a message is showing. Idle at home: no timer at all.
    private func updatePolling() {
        let needed = target != home || hintShownAt != nil
        if needed, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
        } else if !needed {
            timer?.invalidate()
            timer = nil
        }
    }

    func tick(cursor: CGPoint, optionHeld: Bool, fileDragging: Bool = false, now: Double) {
        defer { updatePolling() }
        if pill.isDragging || imageView.isDragging { return }
        if let shown = hintShownAt, optionHeld || now - shown > 3 { hideHint() }

        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: home.midX, y: home.midY)) } ?? NSScreen.main
        guard let screen else { return }
        let bypass = editing || optionHeld || fileDragging || !defaults.bool(forKey: Setting.dodgeEnabled)
        let next = nextFrame(home: home, current: target, cursor: cursor, visible: screen.frame,
                             proximity: defaults.double(forKey: Setting.dodgeDistance), bypass: bypass)
        guard next != target else { return }
        target = next
        panel.setFrame(next, display: true, animate: true)

        if next != home, reach.recordDodge(at: now), defaults.bool(forKey: Setting.showReachHint) {
            showHint(at: now)
        }
    }

    private func showHint(at now: Double) { showMessage(Self.reachHint, at: now) }

    /// Briefly show `text` in the pill instead of the focus (cleared by tick after 3s or on ⌥).
    private func showMessage(_ text: String, at now: Double = ProcessInfo.processInfo.systemUptime) {
        hintShownAt = now
        field.stringValue = text
        layout()
        updatePolling()
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
        defaults.set([home.midX, home.midY], forKey: Setting.home)
    }

    @objc func beginEditing() {
        if hintShownAt != nil { hideHint() }
        editing = true
        pill.isEditing = true
        field.isEditable = true
        field.isSelectable = true
        NSApp.activate()
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
        defaults.removeObject(forKey: Setting.home)
        layout()
    }
}
