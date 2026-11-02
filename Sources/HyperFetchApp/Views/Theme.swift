//
//  Theme.swift
//  HyperFetchApp
//
//  Design tokens and dynamic color definitions supporting Obsidian Sequoia
//  (macOS Sequoia Dark Mode & Apple Native Light Mode).
//

import AppKit
import SwiftUI

/// Dynamic theme tokens and design system constants for HyperFetch.
public enum Theme {
    // MARK: - Corner Radii

    public static let cornerRadiusSmall: CGFloat = 4
    public static let cornerRadiusMedium: CGFloat = 8
    public static let cornerRadiusLarge: CGFloat = 12
    public static let cornerRadiusModal: CGFloat = 20

    // MARK: - Dynamic Canvas & Surface Colors

    /// Foundation level canvas behind split views and main content area.
    public static let canvasBackground = Color.dynamic(
        dark: NSColor(hex: 0x0d0e12),
        light: NSColor(hex: 0xF5F5F7)
    )

    /// Primary window background surface.
    public static let windowSurface = Color.dynamic(
        dark: NSColor(hex: 0x141518),
        light: NSColor(hex: 0xFFFFFF)
    )

    /// Left sidebar container background.
    public static let sidebarBackground = Color.dynamic(
        dark: NSColor(hex: 0x16181d),
        light: NSColor(hex: 0xF3F4F6)
    )

    /// Top window toolbar background.
    public static let toolbarBackground = Color.dynamic(
        dark: NSColor(hex: 0x1a1c22),
        light: NSColor(hex: 0xFAFAFC)
    )

    /// Right inspector panel background.
    public static let inspectorBackground = Color.dynamic(
        dark: NSColor(hex: 0x181a20),
        light: NSColor(hex: 0xF9FAFB)
    )

    /// Inactive card container surface.
    public static let cardBackground = Color.dynamic(
        dark: NSColor(hex: 0x1c1e24),
        light: NSColor(hex: 0xFFFFFF)
    )

    /// Active / selected card container surface.
    public static let cardActive = Color.dynamic(
        dark: NSColor(hex: 0x20242f),
        light: NSColor(hex: 0xF0F4FF)
    )

    /// Subtle card hairline border.
    public static let cardBorder = Color.dynamic(
        dark: NSColor(white: 1.0, alpha: 0.08),
        light: NSColor(white: 0.0, alpha: 0.08)
    )

    /// Active / selected card highlight border.
    public static let cardBorderActive = Color.dynamic(
        dark: NSColor(hex: 0x0a84ff, alpha: 0.40),
        light: NSColor(hex: 0x007aff, alpha: 0.30)
    )

    /// Card hover highlight.
    public static let cardHover = Color.dynamic(
        dark: NSColor(white: 1.0, alpha: 0.04),
        light: NSColor(white: 0.0, alpha: 0.03)
    )

    /// Subtle pill / tag background.
    public static let tagBackground = Color.dynamic(
        dark: NSColor(white: 1.0, alpha: 0.06),
        light: NSColor(white: 0.0, alpha: 0.05)
    )

    /// Input field background.
    public static let inputBackground = Color.dynamic(
        dark: NSColor(hex: 0x14161d),
        light: NSColor(hex: 0xFFFFFF)
    )

    /// Input field border.
    public static let inputBorder = Color.dynamic(
        dark: NSColor(white: 1.0, alpha: 0.14),
        light: NSColor(hex: 0xD1D1D6)
    )

    /// Status bar and footer background.
    public static let statusBarBackground = Color.dynamic(
        dark: NSColor(hex: 0x14161c),
        light: NSColor(hex: 0xF0F1F3)
    )

    /// General separator line.
    public static let separator = Color.dynamic(
        dark: NSColor(white: 1.0, alpha: 0.08),
        light: NSColor(white: 0.0, alpha: 0.08)
    )

    // MARK: - Dynamic Text Colors

    /// Primary high-contrast text.
    public static let textPrimary = Color.dynamic(
        dark: NSColor(hex: 0xf3f4f8),
        light: NSColor(hex: 0x1D1D1F)
    )

    /// Secondary supporting text and readout labels.
    public static let textSecondary = Color.dynamic(
        dark: NSColor(hex: 0x9da3b0),
        light: NSColor(hex: 0x6E6E73)
    )

    /// Tertiary captions, shortcuts, and inactive elements.
    public static let textTertiary = Color.dynamic(
        dark: NSColor(hex: 0x686f7e),
        light: NSColor(hex: 0x86868B)
    )

    // MARK: - Accent & Semantic Colors

    /// Electric System Blue accent.
    public static let accent = Color.dynamic(
        dark: NSColor(hex: 0x0a84ff),
        light: NSColor(hex: 0x007AFF)
    )

    /// Sequoia Green (success, 2xx, optimal).
    public static let success = Color(hex: 0x30d158)

    /// Sequoia Amber (warnings, paused, redirects).
    public static let warning = Color(hex: 0xff9f0a)

    /// Sequoia Crimson (errors, critical, failed).
    public static let critical = Color(hex: 0xff453a)

    // MARK: - File Format Badges & Colors

    /// Returns a badge style (gradient colors, text color, label) for a given file extension.
    public static func fileBadge(for extensionName: String) -> FileBadgeStyle {
        let ext = extensionName.lowercased().trimmingCharacters(in: .punctuationCharacters)
        switch ext {
        case "xip", "zip", "tar", "gz", "7z", "rar", "bz2", "xz":
            return FileBadgeStyle(
                label: ext.isEmpty ? "ZIP" : ext.uppercased(),
                systemIcon: "archivebox.fill",
                gradientTop: Color(hex: 0x1e3a8a).opacity(0.7),
                gradientBottom: Color(hex: 0x172554).opacity(0.85),
                tintColor: Color(hex: 0x60a5fa),
                borderColor: Color(hex: 0x3b82f6).opacity(0.35)
            )
        case "iso", "img":
            return FileBadgeStyle(
                label: "ISO",
                systemIcon: "opticaldisc.fill",
                gradientTop: Color(hex: 0x451a03).opacity(0.7),
                gradientBottom: Color(hex: 0x7c2d12).opacity(0.85),
                tintColor: Color(hex: 0xfbbf24),
                borderColor: Color(hex: 0xf59e0b).opacity(0.35)
            )
        case "pkg", "mpkg":
            return FileBadgeStyle(
                label: "PKG",
                systemIcon: "shippingbox.fill",
                gradientTop: Color(hex: 0x064e3b).opacity(0.7),
                gradientBottom: Color(hex: 0x042f2e).opacity(0.85),
                tintColor: Color(hex: 0x34d399),
                borderColor: Color(hex: 0x10b981).opacity(0.35)
            )
        case "dmg":
            return FileBadgeStyle(
                label: "DMG",
                systemIcon: "externaldrive.fill.badge.plus",
                gradientTop: Color(hex: 0x312e81).opacity(0.7),
                gradientBottom: Color(hex: 0x1e1b4b).opacity(0.85),
                tintColor: Color(hex: 0x818cf8),
                borderColor: Color(hex: 0x6366f1).opacity(0.35)
            )
        case "pdf", "doc", "docx", "txt", "rtf", "pages":
            return FileBadgeStyle(
                label: ext.isEmpty ? "DOC" : ext.uppercased(),
                systemIcon: "doc.fill",
                gradientTop: Color(hex: 0x1e293b).opacity(0.7),
                gradientBottom: Color(hex: 0x0f172a).opacity(0.85),
                tintColor: Color(hex: 0x38bdf8),
                borderColor: Color(hex: 0x0ea5e9).opacity(0.35)
            )
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return FileBadgeStyle(
                label: ext.isEmpty ? "VID" : ext.uppercased(),
                systemIcon: "film.fill",
                gradientTop: Color(hex: 0x3b0764).opacity(0.7),
                gradientBottom: Color(hex: 0x2e1065).opacity(0.85),
                tintColor: Color(hex: 0xc084fc),
                borderColor: Color(hex: 0xa855f7).opacity(0.35)
            )
        case "mp3", "m4a", "flac", "wav", "aac", "ogg":
            return FileBadgeStyle(
                label: ext.isEmpty ? "AUD" : ext.uppercased(),
                systemIcon: "music.note",
                gradientTop: Color(hex: 0x831843).opacity(0.7),
                gradientBottom: Color(hex: 0x500724).opacity(0.85),
                tintColor: Color(hex: 0xf472b6),
                borderColor: Color(hex: 0xec4899).opacity(0.35)
            )
        case "app":
            return FileBadgeStyle(
                label: "APP",
                systemIcon: "app.fill",
                gradientTop: Color(hex: 0x1e3a8a).opacity(0.7),
                gradientBottom: Color(hex: 0x172554).opacity(0.85),
                tintColor: Color(hex: 0x60a5fa),
                borderColor: Color(hex: 0x3b82f6).opacity(0.35)
            )
        default:
            let defaultLabel = ext.isEmpty ? "FILE" : (ext.count <= 4 ? ext.uppercased() : String(ext.prefix(4)).uppercased())
            return FileBadgeStyle(
                label: defaultLabel,
                systemIcon: "doc.fill",
                gradientTop: Color(hex: 0x1f2937).opacity(0.7),
                gradientBottom: Color(hex: 0x111827).opacity(0.85),
                tintColor: Color(hex: 0x9ca3af),
                borderColor: Color(hex: 0x6b7280).opacity(0.35)
            )
        }
    }
}

public struct FileBadgeStyle {
    public let label: String
    public let systemIcon: String
    public let gradientTop: Color
    public let gradientBottom: Color
    public let tintColor: Color
    public let borderColor: Color
}

// MARK: - Color & NSColor Helpers

extension NSColor {
    public convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Color {
    public init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}
