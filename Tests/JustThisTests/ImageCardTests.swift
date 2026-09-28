import AppKit
import Testing
@testable import JustThis
import JustThisCore

/// PNG bytes for a solid w×h image.
func pngData(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
struct ImageCardTests {
    let defaults = UserDefaults(suiteName: "JustThisTests-\(UUID())")!
    let storage = FileManager.default.temporaryDirectory.appendingPathComponent("JustThisTests-\(UUID())")
    let board = NSPasteboard(name: NSPasteboard.Name("JustThisTests-\(UUID())"))
    let app = { let a = NSApplication.shared; a.setActivationPolicy(.accessory); return a }()

    func launch() -> AppDelegate {
        let d = AppDelegate(defaults: defaults, storage: storage)
        d.pasteboard = board
        d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return d
    }

    func paste(_ d: AppDelegate, _ write: (NSPasteboard) -> Void) async -> Bool {
        board.clearContents()
        write(board)
        return await d.pasteImage(from: board)
    }

    @Test func pastingImageDataShowsItUnderThePillAndPersists() async {
        let d = launch()
        let pillOnly = d.panel.frame
        let ok = await paste(d) { $0.setData(pngData(width: 400, height: 200), forType: .png) }
        #expect(ok)
        #expect(!d.imageView.isHidden)
        #expect(d.panel.frame.height > pillOnly.height + 50)
        #expect(d.imageView.frame.maxY <= d.pill.frame.minY) // image sits under the pill
        // A fresh launch brings the image back.
        let again = AppDelegate(defaults: defaults, storage: storage)
        again.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(!again.imageView.isHidden)
    }

    @Test func pastingAnImageURLLoadsIt() async throws {
        let d = launch()
        let file = storage.deletingLastPathComponent().appendingPathComponent("jt-\(UUID()).png")
        try pngData(width: 120, height: 120).write(to: file)
        let ok = await paste(d) { $0.setString(file.absoluteString, forType: .string) }
        #expect(ok)
        #expect(!d.imageView.isHidden)
    }

    @Test func pastingACopiedImageFileLoadsIt() async throws {
        let d = launch()
        let file = storage.deletingLastPathComponent().appendingPathComponent("jt-\(UUID()).png")
        try pngData(width: 90, height: 60).write(to: file)
        let ok = await paste(d) { $0.writeObjects([file as NSURL]) }
        #expect(ok)
        #expect(!d.imageView.isHidden)
    }

    @Test func pastingPlainTextIsIgnored() async {
        let d = launch()
        let ok = await paste(d) { $0.setString("not an image", forType: .string) }
        #expect(!ok)
        #expect(d.imageView.isHidden)
    }

    @Test func pastingANonImageFileIsRejected() async throws {
        let d = launch()
        let file = storage.deletingLastPathComponent().appendingPathComponent("jt-\(UUID()).txt")
        try Data("hello".utf8).write(to: file)
        let ok = await paste(d) { $0.setString(file.absoluteString, forType: .string) }
        #expect(!ok)
        #expect(d.imageView.isHidden)
    }

    @Test func removingTheImageShrinksBackToThePill() async {
        let d = launch()
        let pillOnly = d.panel.frame.height
        _ = await paste(d) { $0.setData(pngData(width: 300, height: 300), forType: .png) }
        d.removeImage()
        #expect(d.imageView.isHidden)
        #expect(d.panel.frame.height == pillOnly)
        let again = AppDelegate(defaults: defaults, storage: storage)
        again.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(again.imageView.isHidden)
    }

    @Test func imageWidthSettingResizesLiveKeepingAspect() async {
        let d = launch()
        _ = await paste(d) { $0.setData(pngData(width: 400, height: 200), forType: .png) }
        defaults.set(360.0, forKey: Setting.imageWidth)
        #expect(d.imageView.frame.size == CGSize(width: 360, height: 180))
    }

    @Test func draggingTheCornerResizesAndKeepsTopLeftFixed() async {
        let d = launch()
        _ = await paste(d) { $0.setData(pngData(width: 400, height: 200), forType: .png) }
        let before = d.imageView.frame.width
        let topLeft = CGPoint(x: d.panel.frame.minX, y: d.panel.frame.maxY)
        func event(_ type: NSEvent.EventType, _ screen: CGPoint) -> NSEvent {
            let o = d.panel.frame.origin
            return NSEvent.mouseEvent(with: type, location: CGPoint(x: screen.x - o.x, y: screen.y - o.y), modifierFlags: .option,
                                      timestamp: 0, windowNumber: d.panel.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1, pressure: 1)!
        }
        let corner = d.imageView.convert(CGPoint(x: d.imageView.bounds.maxX - 3, y: d.imageView.bounds.minY + 3), to: nil)
        let start = d.panel.convertPoint(toScreen: corner)
        d.imageView.mouseDown(with: event(.leftMouseDown, start))
        d.imageView.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: start.x + 100, y: start.y - 50)))
        d.imageView.mouseUp(with: event(.leftMouseUp, CGPoint(x: start.x + 100, y: start.y - 50)))
        #expect(d.imageView.frame.width == before + 100)
        #expect(abs(defaults.double(forKey: Setting.imageWidth) - (before + 100)) < 1)
        #expect(abs(d.panel.frame.minX - topLeft.x) < 1 && abs(d.panel.frame.maxY - topLeft.y) < 1)
    }

    @Test func commandVOnThePillPastes() async {
        let d = launch()
        board.clearContents()
        board.setData(pngData(width: 50, height: 50), forType: .png)
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                 windowNumber: d.panel.windowNumber, context: nil, characters: "v",
                                 charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        #expect(d.panel.performKeyEquivalent(with: e))
        for _ in 0..<50 where d.imageView.isHidden { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(!d.imageView.isHidden)
    }

    @Test func dodgingPausesWhileAFileIsBeingDragged() {
        let d = launch()
        let home = d.panel.frame
        d.tick(cursor: CGPoint(x: home.midX, y: home.midY), optionHeld: false, fileDragging: true, now: 0)
        #expect(d.panel.frame == home)
    }
}

@MainActor
struct PasteWhileEditingTests {
    let defaults = UserDefaults(suiteName: "JustThisTests-\(UUID())")!
    let storage = FileManager.default.temporaryDirectory.appendingPathComponent("JustThisTests-\(UUID())")
    let board = NSPasteboard(name: NSPasteboard.Name("JustThisTests-\(UUID())"))
    let app = { let a = NSApplication.shared; a.setActivationPolicy(.accessory); return a }()

    func launchEditing() -> AppDelegate {
        let d = AppDelegate(defaults: defaults, storage: storage)
        d.pasteboard = board
        d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        d.beginEditing() // focus text selected, like double-clicking the pill
        return d
    }

    var commandV: NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
    }

    @Test func imageOnClipboardPastesAsImageEvenWhileEditing() async {
        let d = launchEditing()
        board.clearContents()
        board.setData(pngData(width: 80, height: 40), forType: .png)
        #expect(d.panel.performKeyEquivalent(with: commandV))
        for _ in 0..<50 where d.imageView.isHidden { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(!d.imageView.isHidden)
    }

    @Test func textOnClipboardStillPastesAsTextWhileEditing() async {
        let d = launchEditing()
        board.clearContents()
        board.setString("https://example.com/cat.png", forType: .string)
        #expect(!d.panel.performKeyEquivalent(with: commandV)) // left to the text field
        try? await Task.sleep(for: .milliseconds(200))
        #expect(d.imageView.isHidden)
    }
}
