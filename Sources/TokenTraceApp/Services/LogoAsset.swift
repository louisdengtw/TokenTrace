import AppKit
import Foundation
import OSLog

/// Loads the TokenTrace app icon from the bundle and exposes it as a small
/// PNG base64 data URI, suitable for inlining into the exported HTML/PDF.
/// Embedding rather than referencing keeps the report fully self-contained.
enum LogoAsset {
    private static let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "LogoAsset")

    /// 1×1 transparent PNG, used when the app icon can't be loaded so the
    /// imprint layout doesn't break with a broken-image placeholder.
    private static let transparentFallback =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    /// Returns a `data:image/png;base64,…` URI for the bundled `.icns` icon,
    /// rendered down to `size × size` points. Falls back to a 1×1 transparent
    /// pixel if the icon is missing or PNG encoding fails.
    static func bundledDataURI(size: CGFloat = 64) -> String {
        // build-app.sh ships TokenTrace.icns inside .app/Contents/Resources,
        // which makes it discoverable via Bundle.main resource APIs.
        guard let url = Bundle.main.url(forResource: "TokenTrace", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            log.warning("TokenTrace.icns not found in main bundle; using transparent fallback")
            return transparentFallback
        }
        let target = NSSize(width: size, height: size)
        let scaled = NSImage(size: target)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        scaled.unlockFocus()

        guard let tiff = scaled.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            log.warning("Failed to encode TokenTrace icon as PNG; using transparent fallback")
            return transparentFallback
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
