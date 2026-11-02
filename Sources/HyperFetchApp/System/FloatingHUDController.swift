//
//  FloatingHUDController.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import SwiftUI
import DownloadKit

/// Manages the lifecycle, positioning, and animation of the floating Quick-Add HUD window.
@MainActor
public final class FloatingHUDController: NSObject {
    public static let shared = FloatingHUDController()

    private var panel: NSPanel?
    private var autoDismissTask: Task<Void, Never>?
    private let autoDismissTimeout: TimeInterval = 10.0

    private override init() {
        super.init()
    }

    /// Displays the Floating HUD window anchored at the top-right of the user's primary screen.
    public func show(
        url: URL,
        filename: String,
        appState: AppState
    ) {
        // Cancel any pending auto-dismiss timer
        autoDismissTask?.cancel()

        // Create or configure the NSPanel
        let hudPanel: NSPanel
        if let existing = self.panel {
            hudPanel = existing
        } else {
            hudPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                backing: .buffered,
                defer: false
            )
            hudPanel.level = .floating
            hudPanel.isFloatingPanel = true
            hudPanel.hidesOnDeactivate = false
            hudPanel.isMovableByWindowBackground = true
            hudPanel.isOpaque = false
            hudPanel.backgroundColor = .clear
            hudPanel.hasShadow = false // Shadow handled by SwiftUI material overlay
            hudPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = hudPanel
        }

        // Host SwiftUI QuickAddHUDView
        let hudView = QuickAddHUDView(
            url: url,
            filename: filename,
            onDownloadNow: { [weak self] in
                self?.dismiss()
                if appState.bringToFrontOnCapture {
                    appState.bringToFront()
                }
                appState.addTask(url: url, filename: filename, autoStart: true)
            },
            onCustomize: { [weak self] in
                self?.dismiss()
                appState.presentAddSheet(url: url.absoluteString, filename: filename)
                appState.bringToFront()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
        hudPanel.contentView = hostingView

        // Position panel at top-right with margin
        positionPanel(hudPanel)

        // Present panel
        hudPanel.alphaValue = 0.0
        hudPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            hudPanel.animator().alphaValue = 1.0
        }

        // Schedule auto-dismiss
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.autoDismissTimeout ?? 10 * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Dismisses and hides the floating HUD window.
    public func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        guard let hudPanel = self.panel, hudPanel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            hudPanel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                hudPanel.orderOut(nil)
                self?.panel = nil
            }
        })
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 160
        let margin: CGFloat = 20

        let x = screenFrame.maxX - panelWidth - margin
        let y = screenFrame.maxY - panelHeight - margin

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}
