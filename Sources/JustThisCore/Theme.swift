import Foundation

public struct RGB: Equatable, Sendable {
    public let r, g, b: Double
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
}

/// A pill look: a tint laid over the blur, text, and the breathing dot.
public struct Theme: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let background: RGB
    public let text: RGB
    public let accent: RGB
    /// Dark themes use the dark blur material; light ones the light.
    public let isDark: Bool
}

public enum Themes {
    /// First entry is the default.
    public static let all: [Theme] = [
        Theme(id: "paper", name: "Paper", background: RGB(hex: 0xF6F1E7), text: RGB(hex: 0x1F1B16), accent: RGB(hex: 0xD9480F), isDark: false),
        Theme(id: "ember", name: "Ember", background: RGB(hex: 0x1C1B1F), text: RGB(hex: 0xFFFFFF), accent: RGB(hex: 0xFF9E1A), isDark: true),
        Theme(id: "ocean", name: "Ocean", background: RGB(hex: 0x0E1F3D), text: RGB(hex: 0xE6F0FF), accent: RGB(hex: 0x4FD1FF), isDark: true),
        Theme(id: "forest", name: "Forest", background: RGB(hex: 0x13261C), text: RGB(hex: 0xEAF3E6), accent: RGB(hex: 0x9BE564), isDark: true),
        Theme(id: "rose", name: "Rose", background: RGB(hex: 0x2A1420), text: RGB(hex: 0xFFE8F0), accent: RGB(hex: 0xFF6FA3), isDark: true),
        Theme(id: "mono", name: "Mono", background: RGB(hex: 0x000000), text: RGB(hex: 0xFFFFFF), accent: RGB(hex: 0xFFFFFF), isDark: true),
    ]

    public static var `default`: Theme { all[0] }

    public static func named(_ id: String?) -> Theme {
        all.first { $0.id == id } ?? Self.default
    }
}

/// WCAG 2 contrast ratio, 1...21.
public func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }
    let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
    return (hi + 0.05) / (lo + 0.05)
}
