//
//  DockTileController.swift
//  SwiftFlowApp
//

import AppKit

/// Updates the macOS Dock icon badge with the number of active downloads.
@MainActor
public enum DockTileController {
    public static func updateBadge(activeCount: Int) {
        if activeCount > 0 {
            NSApp.dockTile.badgeLabel = "\(activeCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }
}
