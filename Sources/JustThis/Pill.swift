import AppKit
import JustThisCore

/// Borderless panel that floats above everything, on every Space, including full-screen apps.
final class PillPanel: NSPanel {
    /// ⌘, from the pill. Menu shortcuts only reach an active app, and macOS often won't activate
    /// a background app, so the (non-activating, but key) pill handles it itself.
    var onSettingsShortcut: () -> Void = {}
    /// ⌘V / Edit › Paste while not typing in the focus field: paste an image.
    var onPaste: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.12 }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if command, event.charactersIgnoringModifiers == "," {
            onSettingsShortcut()
            return true
        }
        if command, event.charactersIgnoringModifiers == "v", !(firstResponder is NSText) {
            onPaste()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) { onPaste() }
}

/// The capsule. Owns clicks (the label never sees them): double-click edits, drag moves,
/// right-click shows the app menu.
///
/// Dragging is done by hand rather than with `performDrag`: that hands the move to the system,
/// which finishes asynchronously and applies its own edge behaviour, so the pill landed on a
/// screen edge instead of where it was dropped.
final class PillView: NSVisualEffectView {
    var onDoubleClick: () -> Void = {}
    var onMoved: () -> Void = {}
    var isEditing = false
    /// Cursor offset from the window origin while dragging; nil otherwise.
    private var grab: CGPoint?
    var isDragging: Bool { grab != nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        isEditing ? super.hitTest(point) : (frame.contains(point) ? self : nil)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey() // so ⌘, reaches the pill without activating the app
        if event.clickCount == 2 { onDoubleClick(); return }
        grab = event.locationInWindow
    }
    override func mouseDragged(with event: NSEvent) {
        guard let grab, let window else { return }
        let cursor = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(CGPoint(x: cursor.x - grab.x, y: cursor.y - grab.y))
    }
    override func mouseUp(with event: NSEvent) {
        guard grab != nil else { return }
        grab = nil
        onMoved()
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

extension NSColor {
    convenience init(_ c: RGB) { self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
}
