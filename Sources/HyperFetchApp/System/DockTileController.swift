//
//  DockTileController.swift
//  HyperFetchApp
//

import AppKit

/// Updates the macOS Dock icon badge and draws a live progress bar overlay on the app icon.
@MainActor
public final class DockTileController {
    private static let progressView = DockProgressView()

    public static func update(activeCount: Int, progress: Double = 0.0) {
        if activeCount > 0 {
            NSApp.dockTile.badgeLabel = "\(activeCount)"
            progressView.progress = progress
            if NSApp.dockTile.contentView !== progressView {
                NSApp.dockTile.contentView = progressView
            }
            NSApp.dockTile.display()
        } else {
            NSApp.dockTile.badgeLabel = nil
            if NSApp.dockTile.contentView != nil {
                NSApp.dockTile.contentView = nil
                NSApp.dockTile.display()
            }
        }
    }

    public static func updateBadge(activeCount: Int) {
        update(activeCount: activeCount, progress: 0.0)
    }
}

/// Custom NSView rendering the application icon with a native progress bar overlay at the bottom.
final class DockProgressView: NSView {
    var progress: Double = 0.0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw standard app icon
        if let icon = NSApp.applicationIconImage {
            icon.draw(in: bounds)
        }

        // Draw rounded bottom progress bar pill
        guard progress > 0 else { return }
        let barHeight: CGFloat = 16
        let barMargin: CGFloat = 12
        let barRect = NSRect(
            x: barMargin,
            y: barMargin,
            width: bounds.width - (barMargin * 2),
            height: barHeight
        )
        let backgroundPath = NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        NSColor(calibratedWhite: 0.1, alpha: 0.85).setFill()
        backgroundPath.fill()

        // Border
        NSColor(calibratedWhite: 1.0, alpha: 0.25).setStroke()
        backgroundPath.lineWidth = 1.0
        backgroundPath.stroke()

        // Progress fill
        let fillWidth = max(barHeight, (barRect.width - 2) * CGFloat(min(1.0, max(0.0, progress))))
        let fillRect = NSRect(
            x: barRect.minX + 1,
            y: barRect.minY + 1,
            width: fillWidth,
            height: barHeight - 2
        )
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: (barHeight - 2) / 2, yRadius: (barHeight - 2) / 2)
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0).setFill()
        fillPath.fill()
    }
}

