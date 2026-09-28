import AppKit
import Testing
@testable import JustThis

/// A fresh temp folder for the image store, so tests never read or write the real app's data.
func scratchStorage() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("JustThisTests-\(UUID())")
}

/// Drives the real panel + field editor: begin editing, type, then Return / Escape
/// through the same delegate command path a keyboard uses.
@MainActor
struct EditingTests {
    let defaults = UserDefaults(suiteName: "JustThisTests-\(UUID())")!
    let app = { let a = NSApplication.shared; a.setActivationPolicy(.accessory); return a }()

    func launch() -> AppDelegate {
        let d = AppDelegate(defaults: defaults, storage: scratchStorage())
        d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return d
    }

    func type(_ d: AppDelegate, _ text: String, then command: Selector) throws {
        d.beginEditing()
        let editor = try #require(d.field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: editor.selectedRange())
        editor.doCommand(by: command)
    }

    @Test func returnCommitsAndPersistsFocus() throws {
        let d = launch()
        try type(d, "Ship Just This", then: #selector(NSResponder.insertNewline(_:)))
        #expect(d.field.stringValue == "Ship Just This")
        #expect(defaults.string(forKey: "focus") == "Ship Just This")
        #expect(!d.field.isEditable)
        // Handing focus back to the previous app must not hide the pill with it.
        #expect(d.panel.isVisible)
    }

    @Test func escapeCancelsAndKeepsOldFocus() throws {
        let d = launch()
        d.focus = "Old focus"
        d.field.stringValue = "Old focus"
        try type(d, "Distraction", then: #selector(NSResponder.cancelOperation(_:)))
        #expect(d.field.stringValue == "Old focus")
        #expect(defaults.string(forKey: "focus") == "Old focus")
    }

    @Test func pillGrowsToFitLongerFocus() throws {
        let d = launch()
        let before = d.panel.frame.width
        try type(d, "A considerably longer focus statement for today", then: #selector(NSResponder.insertNewline(_:)))
        #expect(d.panel.frame.width > before)
        #expect(d.panel.level == .statusBar)
        #expect(d.panel.collectionBehavior.contains(.canJoinAllSpaces))
    }
}
