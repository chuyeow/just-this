import AppKit

/// Borderless panel that floats above everything, on every Space, including full-screen apps.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.12 }
}

/// The capsule. Owns clicks (the label never sees them): double-click edits, drag moves,
/// right-click shows the app menu.
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
    override func rightMouseDown(with event: NSEvent) {
        if let menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}
