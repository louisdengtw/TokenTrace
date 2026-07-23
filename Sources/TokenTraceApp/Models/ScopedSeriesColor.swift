import SwiftUI

/// Deterministic per-model colors for model-scoped weekly series, readable on
/// both light and dark chart backgrounds (Okabe-Ito-derived). "Sonnet" keeps
/// the bluish-green it shipped with so historical charts stay recognizable.
enum ScopedSeriesColor {
    private static let sonnetHex = "#009E73"
    // Excludes the fixed-bucket report colors (#0072B2, #D55E00) and the
    // Sonnet green so scoped series never collide with them.
    private static let rotation = ["#CC79A7", "#E69F00", "#56B4E9"]

    static func hex(for model: String) -> String {
        if model == "Sonnet" { return sonnetHex }
        // FNV-1a over the name: stable across launches and ranges.
        var hash: UInt32 = 2_166_136_261
        for byte in model.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return rotation[Int(hash % UInt32(rotation.count))]
    }

    static func color(for model: String) -> Color {
        let hex = hex(for: model)
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
