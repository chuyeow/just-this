import CoreGraphics
import Foundation

public enum ImageSizing {
    public static let minWidth: CGFloat = 80
    public static let maxWidth: CGFloat = 800

    /// Display size at `width` (clamped), keeping the image's aspect ratio.
    public static func size(natural: CGSize, width: CGFloat) -> CGSize {
        let w = min(max(width, minWidth), maxWidth)
        let aspect = natural.width > 0 && natural.height > 0 ? natural.height / natural.width : 1
        return CGSize(width: w, height: (w * aspect).rounded())
    }
}

/// Where the pill and the optional image sit inside the floating card (AppKit coords, y up):
/// pill on top, image below, both centred horizontally.
public struct CardLayout: Equatable {
    public let size: CGSize
    public let pill: CGRect
    public let image: CGRect?
}

public func cardLayout(pill: CGSize, image: CGSize?, gap: CGFloat) -> CardLayout {
    guard let image else {
        return CardLayout(size: pill, pill: CGRect(origin: .zero, size: pill), image: nil)
    }
    let width = max(pill.width, image.width)
    let height = pill.height + gap + image.height
    return CardLayout(
        size: CGSize(width: width, height: height),
        pill: CGRect(x: ((width - pill.width) / 2).rounded(), y: height - pill.height, width: pill.width, height: pill.height),
        image: CGRect(x: ((width - image.width) / 2).rounded(), y: 0, width: image.width, height: image.height)
    )
}

/// A pasted string that points at an image we can load: http(s) with a host, or a file URL.
public func imageURL(fromPasted text: String) -> URL? {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = url.scheme?.lowercased() else { return nil }
    switch scheme {
    case "http", "https": return url.host?.isEmpty == false ? url : nil
    case "file": return url.path.isEmpty ? nil : url
    default: return nil
    }
}
