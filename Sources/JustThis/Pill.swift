import AppKit
import JustThisCore

/// Borderless panel that floats above everything, on every Space, including full-screen apps.
final class PillPanel: NSPanel {
    /// ⌘, while the pill is key (after a click has activated the app, or while editing).
    var onSettingsShortcut: () -> Void = {}
    /// ⌘V on the pill. Given whether the focus text is being edited; returns true if it pasted an
    /// image, false to let the text field paste text as usual.
    var onPaste: (_ editingText: Bool) -> Bool = { _ in false }

    override var canBecomeKey: Bool { true }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.12 }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if command, event.charactersIgnoringModifiers == "," {
            onSettingsShortcut()
            return true
        }
        if command, event.charactersIgnoringModifiers == "v", onPaste(firstResponder is NSText) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) { _ = onPaste(false) }
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
    /// A click that wasn't a drag.
    var onClick: () -> Void = {}
    var isEditing = false
    /// Cursor offset from the window origin while dragging; nil otherwise.
    private var grab: CGPoint?
    private var moved = false
    var isDragging: Bool { grab != nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        isEditing ? super.hitTest(point) : (frame.contains(point) ? self : nil)
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick(); return }
        grab = event.locationInWindow
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let grab, let window else { return }
        moved = true
        let cursor = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(CGPoint(x: cursor.x - grab.x, y: cursor.y - grab.y))
    }
    override func mouseUp(with event: NSEvent) {
        guard grab != nil else { return }
        grab = nil
        moved ? onMoved() : onClick()
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

extension NSColor {
    convenience init(_ c: RGB) { self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
}
