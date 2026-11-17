//
//  MainWindowDelegate.swift
//  HyperFetchApp
//

import AppKit

@MainActor
public final class MainWindowDelegate: NSObject, NSWindowDelegate {
    public static let shared = MainWindowDelegate()
    public weak var mainWindow: NSWindow?
    public var isTerminating: Bool = false

    private override init() {
        super.init()
    }

    public func configure(window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1000, height: 600)
        window.appearance = NSApp.appearance

        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.toolbarStyle = .unified

        let currentFrame = window.frame
        if currentFrame.width < 1100 || currentFrame.height < 650 {
            window.setContentSize(NSSize(width: 1200, height: 750))
            window.center()
        }

        configureSplitViewItems()
        DispatchQueue.main.async { [weak self] in
            self?.configureSplitViewItems()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.configureSplitViewItems()
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isTerminating {
            return true
        }
        // Hide window instead of destroying it
        sender.orderOut(nil)
        return false
    }

    public func reopenMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            let currentFrame = window.frame
            if currentFrame.width < 1100 || currentFrame.height < 650 {
                window.setContentSize(NSSize(width: 1200, height: 750))
                window.center()
            }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            configureSplitViewItems()
        } else {
            for window in NSApp.windows where window.canBecomeMain {
                window.isOpaque = true
                window.backgroundColor = NSColor.windowBackgroundColor
                let currentFrame = window.frame
                if currentFrame.width < 1100 || currentFrame.height < 650 {
                    window.setContentSize(NSSize(width: 1200, height: 750))
                    window.center()
                }
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                self.mainWindow = window
                configureSplitViewItems()
            }
        }
    }

    public func configureSplitViewItems() {
        guard let splitVC = findSplitViewController() else { return }
        let items = splitVC.splitViewItems
        if items.indices.contains(0) {
            let sidebar = items[0]
            sidebar.canCollapse = false
            sidebar.minimumThickness = 220
            sidebar.maximumThickness = 280
            sidebar.holdingPriority = NSLayoutConstraint.Priority(270)
        }
        if items.indices.contains(1) {
            let content = items[1]
            content.minimumThickness = 440
            content.holdingPriority = NSLayoutConstraint.Priority(200)
        }
        if items.indices.contains(2) {
            let detail = items[2]
            detail.canCollapse = true
            detail.minimumThickness = 320
            detail.maximumThickness = 440
            detail.holdingPriority = NSLayoutConstraint.Priority(260)
        }

        // If the detail pane is active but restored with an undersized width (< 320), reposition dividers
        let splitView = splitVC.splitView
        let totalWidth = splitView.bounds.width
        if totalWidth > 800 && items.count >= 3 {
            let detailView = items[2].viewController.view
            if !items[2].isCollapsed && detailView.frame.width < 320 {
                let sidebarWidth: CGFloat = 240
                let detailWidth: CGFloat = 360
                splitView.setPosition(sidebarWidth, ofDividerAt: 0)
                splitView.setPosition(totalWidth - detailWidth, ofDividerAt: 1)
                splitView.layoutSubtreeIfNeeded()
            }
        }
    }

    public func findSplitViewController() -> NSSplitViewController? {
        guard let window = mainWindow else { return nil }
        if let rootVC = window.contentViewController {
            func findSplitVC(in vc: NSViewController) -> NSSplitViewController? {
                if let splitVC = vc as? NSSplitViewController { return splitVC }
                for child in vc.children {
                    if let found = findSplitVC(in: child) { return found }
                }
                return nil
            }
            if let found = findSplitVC(in: rootVC) {
                return found
            }
        }
        guard let contentView = window.contentView else { return nil }
        func findSplitView(in view: NSView) -> NSSplitView? {
            if let sv = view as? NSSplitView { return sv }
            for sub in view.subviews {
                if let found = findSplitView(in: sub) { return found }
            }
            return nil
        }
        guard let sv = findSplitView(in: contentView) else { return nil }
        if let splitVC = sv.delegate as? NSSplitViewController {
            return splitVC
        }
        var responder: NSResponder? = sv
        while let r = responder {
            if let splitVC = r as? NSSplitViewController {
                return splitVC
            }
            responder = r.nextResponder
        }
        return nil
    }

    public var isDetailCollapsed: Bool {
        guard let splitVC = findSplitViewController(), splitVC.splitViewItems.count > 2 else { return false }
        return splitVC.splitViewItems[2].isCollapsed
    }

    public func toggleDetailPane() {
        guard let splitVC = findSplitViewController(), splitVC.splitViewItems.count > 2 else { return }
        let detailItem = splitVC.splitViewItems[2]
        detailItem.canCollapse = true
        detailItem.minimumThickness = 320
        detailItem.maximumThickness = 440
        detailItem.holdingPriority = NSLayoutConstraint.Priority(260)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            detailItem.animator().isCollapsed.toggle()
        }
    }
}
