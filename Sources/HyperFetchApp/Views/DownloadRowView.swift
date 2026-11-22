//
//  DownloadRowView.swift
//  HyperFetchApp
//
//  Modernized card-based download row item matching the Obsidian Sequoia macOS design system.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Single card row item representing an accelerated download task in the list.
public struct DownloadRowView: View {
    public let task: DownloadTaskModel
    @EnvironmentObject private var appState: AppState

    @ViewState private var isHovered: Bool = false
    @ViewState private var isMoreHovered: Bool = false
    @ViewState private var isActionHovered: Bool = false
    @ViewState private var isFinderHovered: Bool = false

    public init(task: DownloadTaskModel) {
        self.task = task
    }

    public var body: some View {
        let isSelected = appState.selectedTaskIDs.contains(task.id)

        HStack(alignment: .top, spacing: 14) {
            // Checkbox
            Button {
                appState.toggleSelection(id: task.id)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? Theme.accent : Theme.cardBorder.opacity(2.0), lineWidth: 1.2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isSelected ? Theme.accent : Color.white.opacity(0.001))
                        )
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.top, 2)
            .help(isSelected ? "Deselect" : "Select")
            .accessibilityLabel(isSelected ? "Deselect \(task.filename)" : "Select \(task.filename)")
            .accessibilityValue(isSelected ? "Selected" : "Unselected")

            // High Craft File Format Badge Squircle
            fileFormatBadge
                .frame(width: 48, height: 48)

            // Content & Progress Strip
            VStack(alignment: .leading, spacing: 6) {
                // Header: Filename + Badges + Percentage
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(task.filename)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        // Completed Verification Badge
                        if task.status == .completed {
                            ZStack {
                                Circle()
                                    .fill(Theme.success)
                                    .frame(width: 16, height: 16)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x0b2812))
                            }
                            .help("Integrity Verified")
                        }

                        // Multi-Chunk Badge
                        if task.supportsRange && task.status != .completed {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 5, height: 5)
                                Text("Multi-Chunk Accelerated")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Theme.accent.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                    }

                    Spacer()

                    // Trailing Status Pill
                    statusTrailingPill
                }

                // Sleek Dual-Layer Progress Bar
                dualLayerProgressBar

                // Metric Details Strip & Quick Actions
                HStack(alignment: .center) {
                    metricDetailsStrip

                    Spacer()

                    quickActionButtons
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .fill(isSelected ? Theme.cardActive : (isHovered ? Theme.cardHover : Theme.cardBackground))
                .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.shift) {
                        appState.selectRange(to: task.id)
                    } else if NSEvent.modifierFlags.contains(.command) {
                        appState.toggleSelection(id: task.id)
                    } else {
                        appState.selectedTaskId = task.id
                    }
                }
                .onTapGesture(count: 2) {
                    if task.status == .completed {
                        appState.openFile(task: task)
                    }
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .stroke(isSelected ? Theme.cardBorderActive : Theme.cardBorder, lineWidth: isSelected ? 1.5 : 1)
        }
        .shadow(
            color: isSelected ? Theme.accent.opacity(0.18) : Color.black.opacity(0.04),
            radius: isSelected ? 10 : 3,
            x: 0,
            y: isSelected ? 2 : 1.5
        )
        .onHover { isHovered = $0 }
        .modifier(DragCompletedModifier(task: task))
    }

    // MARK: - Subviews

    private var fileFormatBadge: some View {
        let ext = (task.filename as NSString).pathExtension
        let style = Theme.fileBadge(for: ext)

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.gradientTop, style.gradientBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(style.borderColor, lineWidth: 1)
                )

            Image(systemName: style.systemIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(style.tintColor)

            // Extension label badge anchored at bottom
            VStack {
                Spacer()
                Text(style.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(style.tintColor)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var statusTrailingPill: some View {
        Group {
            switch task.status {
            case .downloading:
                Text("\(Int(task.progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
                    )

            case .probing:
                Text("PROBING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.purple)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.purple.opacity(0.45), lineWidth: 1)
                    )

            case .paused:
                HStack(spacing: 5) {
                    Text("PAUSED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.warning)
                    Text("\(Int(task.progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.warning.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.warning.opacity(0.45), lineWidth: 1)
                )

            case .completed:
                Text("DONE • \(AppState.formatBytes(task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.success.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.success.opacity(0.45), lineWidth: 1)
                    )

            case .failed:
                Text("FAILED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.critical.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.critical.opacity(0.45), lineWidth: 1)
                    )

            case .idle:
                Text("QUEUED")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.textTertiary.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.textTertiary.opacity(0.45), lineWidth: 1)
                    )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var dualLayerProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.dynamic(dark: NSColor(hex: 0x13151c), light: NSColor(hex: 0xE8ECF2)))
                    .overlay(
                        Capsule()
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
                    .frame(height: 7)

                // Fill Bar
                let fillRatio = max(0.0, min(1.0, task.progress))
                let fillWidth = CGFloat(fillRatio) * geo.size.width

                Capsule()
                    .fill(progressGradient)
                    .frame(width: fillWidth, height: 7)
                    .animation(.linear(duration: 0.25), value: task.progress)
            }
        }
        .frame(height: 7)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress for \(task.filename)")
        .accessibilityValue("\(Int(task.progress * 100)) percent")
    }

    private var progressGradient: LinearGradient {
        switch task.status {
        case .downloading:
            return LinearGradient(
                colors: [Color.blue, Color(hex: 0x38bdf8), Color(hex: 0x818cf8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .probing:
            return LinearGradient(
                colors: [Color.purple, Color(hex: 0xa855f7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .completed:
            return LinearGradient(
                colors: [Theme.success, Color(hex: 0x47e266)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .paused:
            return LinearGradient(
                colors: [Theme.warning, Color(hex: 0xfbbf24)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .failed:
            return LinearGradient(
                colors: [Theme.critical, Color.pink],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .idle:
            return LinearGradient(
                colors: [Theme.textTertiary.opacity(0.4), Theme.textTertiary.opacity(0.6)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var metricDetailsStrip: some View {
        HStack(spacing: 8) {
            switch task.status {
            case .downloading:
                Text("\(AppState.formatBytes(task.downloadedBytes)) of \(AppState.formatBytes(task.totalBytes))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(AppState.formatSpeed(task.bytesPerSecond))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .help("\(AppState.formatSpeed(task.bytesPerSecond)) (\(String(format: "%.0f", task.bytesPerSecond * 8 / 1_000_000)) Mbps)")
                }
                .foregroundStyle(Theme.success)
                .lineLimit(1)

                let remaining = remainingTimeString
                if !remaining.isEmpty {
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)

                    Text(remaining)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

            case .probing:
                Text("Analyzing remote headers and range support...")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.purple)
                    .lineLimit(1)

            case .paused:
                Text("Paused")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(1)

                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                Text("\(AppState.formatBytes(task.downloadedBytes)) of \(AppState.formatBytes(task.totalBytes))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

            case .completed:
                Text("Completed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.success)
                    .lineLimit(1)

                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)

                Text(AppState.formatBytes(task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                if let completedAt = task.completedAt {
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)

                    Text(completedAt, style: .date)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

            case .failed(let reason):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(reason)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(Theme.critical)
                .help(reason)

            case .idle:
                Text("Waiting in queue...")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
    }

    private var remainingTimeString: String {
        guard task.status == .downloading, task.bytesPerSecond > 0, task.totalBytes > task.downloadedBytes else {
            return ""
        }
        let remainingBytes = task.totalBytes - task.downloadedBytes
        let remainingSeconds = Double(remainingBytes) / task.bytesPerSecond
        if remainingSeconds < 60 {
            return "\(Int(remainingSeconds))s remaining"
        } else if remainingSeconds < 3600 {
            let mins = Int(remainingSeconds / 60)
            let secs = Int(remainingSeconds.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s remaining"
        } else {
            let hours = Int(remainingSeconds / 3600)
            let mins = Int((remainingSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m remaining"
        }
    }

    private var primaryActionHelpText: String {
        if task.status == .downloading || task.status == .probing {
            return "Pause Download"
        } else if task.status == .completed {
            return "Open File"
        } else {
            return "Resume Download"
        }
    }

    private var quickActionButtons: some View {
        HStack(spacing: 4) {
            // Unified Primary Action Button (Pause / Resume / Open)
            Button {
                if task.status == .downloading || task.status == .probing {
                    appState.pause(id: task.id)
                } else if task.status == .completed {
                    appState.openFile(task: task)
                } else {
                    appState.resume(id: task.id)
                }
            } label: {
                Group {
                    if task.status == .downloading || task.status == .probing {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    } else if task.status == .completed {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActionHovered ? Theme.tagBackground : Color.white.opacity(0.001))
                )
                .contentShape(Rectangle())
            }
            .id("task-action-\(task.id)")
            .buttonStyle(.tactile)
            .contentShape(Rectangle())
            .onHover { isActionHovered = $0 }
            .help(primaryActionHelpText)

            // Show in Finder
            Button {
                appState.openInFinder(task: task)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isFinderHovered ? Theme.tagBackground : Color.white.opacity(0.001))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.tactile)
            .contentShape(Rectangle())
            .onHover { isFinderHovered = $0 }
            .help("Show in Finder")

            // More Options Menu
            Menu {
                queuePositionMenu
                Divider()
                Button("Copy Download Link") {
                    DispatchQueue.main.async {
                        appState.copyDownloadLink(task: task)
                    }
                }
                Divider()
                Button("Remove from List") {
                    DispatchQueue.main.async {
                        appState.remove(id: task.id, deleteFile: false)
                    }
                }
                Button("Delete File from Disk...", role: .destructive) {
                    DispatchQueue.main.async {
                        appState.promptDelete(task: task)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isMoreHovered ? Theme.tagBackground : Color.white.opacity(0.001))
                    )
                    .contentShape(Rectangle())
                    .onHover { isMoreHovered = $0 }
            }
            .id("row-more-menu-\(task.id)")
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .contentShape(Rectangle())
            .help("More Options")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var queuePositionMenu: some View {
        let taskIndex = appState.tasks.firstIndex(where: { $0.id == task.id })
        let isFirst = taskIndex == 0
        let isLast = taskIndex == (appState.tasks.count - 1)

        Menu {
            Button {
                DispatchQueue.main.async {
                    appState.moveTaskToTop(id: task.id)
                }
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            .disabled(isFirst)

            Button {
                DispatchQueue.main.async {
                    appState.moveTaskUp(id: task.id)
                }
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(isFirst)

            Button {
                DispatchQueue.main.async {
                    appState.moveTaskDown(id: task.id)
                }
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(isLast)

            Button {
                DispatchQueue.main.async {
                    appState.moveTaskToBottom(id: task.id)
                }
            } label: {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
            .disabled(isLast)
        } label: {
            Label("Queue Position", systemImage: "arrow.up.arrow.down")
        }
        .id("row-queue-menu-\(task.id)")
    }
}

struct DragCompletedModifier: ViewModifier {
    let task: DownloadTaskModel

    func body(content: Content) -> some View {
        if task.status == .completed {
            content.onDrag {
                NSItemProvider(contentsOf: task.destinationURL) ?? NSItemProvider()
            }
        } else {
            content
        }
    }
}
