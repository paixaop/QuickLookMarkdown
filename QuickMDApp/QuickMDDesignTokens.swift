import AppKit
import SwiftUI

/// Stitch QuickMD design tokens (project `8453345261008059249`, light palette).
///
/// **Dark mode:** Light-mode hex values come from Stitch `namedColors`. For `.dark`, use semantic
/// `NSColor` roles (`windowBackgroundColor`, `labelColor`, etc.) until a Stitch dark theme export exists.
enum QuickMDDesignTokens {

    // MARK: - Light (Stitch `namedColors`)

    private static let lightSurface = Color(red: 0.976, green: 0.976, blue: 0.984) // #f9f9fb
    private static let lightSurfaceContainerLow = Color(red: 0.949, green: 0.957, blue: 0.965) // #f2f4f6
    private static let lightSurfaceContainerHigh = Color(red: 0.894, green: 0.914, blue: 0.933) // #e4e9ee
    private static let lightSurfaceContainerHighest = Color(red: 0.867, green: 0.890, blue: 0.914) // #dde3e9
    private static let lightSurfaceContainerLowest = Color.white // #ffffff
    private static let lightPrimary = Color(red: 0, green: 0.357, blue: 0.757) // #005bc1
    private static let lightPrimaryDim = Color(red: 0, green: 0.310, blue: 0.667) // #004faa
    private static let lightOnSurface = Color(red: 0.176, green: 0.200, blue: 0.220) // #2d3338
    private static let lightOnSurfaceVariant = Color(red: 0.349, green: 0.376, blue: 0.396) // #596065
    private static let lightOutlineVariant = Color(red: 0.675, green: 0.702, blue: 0.722) // #acb3b8
    private static let lightPrimaryContainer = Color(red: 0.847, green: 0.886, blue: 1.0) // #d8e2ff

    static let cornerRadiusStitch: CGFloat = 8

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .windowBackgroundColor) : lightSurface
    }

    static func surfaceContainerLow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .controlBackgroundColor) : lightSurfaceContainerLow
    }

    static func surfaceContainerHigh(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .underPageBackgroundColor) : lightSurfaceContainerHigh
    }

    static func surfaceContainerHighest(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.22) : lightSurfaceContainerHighest
    }

    static func surfaceContainerLowest(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .textBackgroundColor) : lightSurfaceContainerLowest
    }

    static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.290, green: 0.565, blue: 1.0) : lightPrimary
    }

    static func primaryDim(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.220, green: 0.478, blue: 0.9) : lightPrimaryDim
    }

    static func onSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .labelColor) : lightOnSurface
    }

    static func onSurfaceVariant(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .secondaryLabelColor) : lightOnSurfaceVariant
    }

    static func outlineVariant(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(nsColor: .separatorColor) : lightOutlineVariant
    }

    static func primaryContainer(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.15, green: 0.22, blue: 0.38).opacity(0.6) : lightPrimaryContainer
    }

    /// Primary as `NSColor` for AppKit (caret, etc.).
    static func primaryNSColor(for scheme: ColorScheme) -> NSColor {
        NSColor(primary(for: scheme))
    }

    static func contentAnimation(duration: Double = 0.2) -> Animation {
        .easeOut(duration: duration)
    }
}
