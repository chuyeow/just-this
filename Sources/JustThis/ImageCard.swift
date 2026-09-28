import AppKit

/// The panel's content: the pill plus an optional image below it. Accepts dropped images.
final class CardView: NSView {
    var onDrop: (NSPasteboard) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .png, .tiff, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop(sender.draggingPasteboard)
        return true
    }
}

/// The image. Dragging its bottom-right corner resizes; dragging elsewhere moves the card.
final class ImageCardView: NSImageView {
    var onResize: (_ width: CGFloat, _ done: Bool) -> Void = { _, _ in }
    var onMoved: () -> Void = {}
    var onClick: () -> Void = {}
    static let grip: CGFloat = 16

    private enum Gesture { case resize(startWidth: CGFloat, startX: CGFloat), move(grab: CGPoint) }
    private var gesture: Gesture?
    private var moved = false
    var isDragging: Bool { gesture != nil }

    private var gripRect: NSRect { NSRect(x: bounds.maxX - Self.grip, y: bounds.minY, width: Self.grip, height: Self.grip) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        moved = false
        let p = convert(event.locationInWindow, from: nil)
        let screenX = window?.convertPoint(toScreen: event.locationInWindow).x ?? 0
        gesture = gripRect.contains(p) ? .resize(startWidth: bounds.width, startX: screenX) : .move(grab: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let gesture else { return }
        moved = true
        let cursor = window.convertPoint(toScreen: event.locationInWindow)
        switch gesture {
        case let .resize(startWidth, startX): onResize(startWidth + cursor.x - startX, false)
        case let .move(grab): window.setFrameOrigin(CGPoint(x: cursor.x - grab.x, y: cursor.y - grab.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let gesture else { return }
        self.gesture = nil
        switch gesture {
        case .resize: onResize(bounds.width, true)
        case .move: moved ? onMoved() : onClick()
        }
    }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(gripRect, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(gripRect, cursor: .crosshair)
        }
    }

    /// A small diagonal grip so the resize corner is discoverable.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let g = gripRect.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath()
        for i in 0..<3 {
            let d = CGFloat(i + 1) * 3.5
            path.move(to: CGPoint(x: g.maxX - d, y: g.minY))
            path.line(to: CGPoint(x: g.maxX, y: g.minY + d))
        }
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 2
        shadow.set()
        path.stroke()
    }
}

/// The current image's original bytes on disk (any format NSImage reads, GIFs keep animating).
struct ImageStore {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("image") }

    static var standard: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Just This")
    }

    func load() -> Data? { try? Data(contentsOf: file) }

    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    func remove() { try? FileManager.default.removeItem(at: file) }
}
