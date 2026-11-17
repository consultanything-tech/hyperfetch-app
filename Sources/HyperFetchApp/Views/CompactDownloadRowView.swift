//
//  CompactDownloadRowView.swift
//  HyperFetchApp
//
//  High-density compact row view maximizing vertical space efficiency.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Dedicated high-density row view (~36pt height) representing an accelerated download task.
public struct CompactDownloadRowView: View {
    public let task: DownloadTaskModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewState private var isHovered: Bool = false
    @ViewState private var isActionHovered: Bool = false
    @ViewState private var isFinderHovered: Bool = false
    @ViewState private var isMoreHovered: Bool = false

    public init(task: DownloadTaskModel) {
        self.task = task
    }

    public var body: some View {
        let isSelected = appState.selectedTaskIDs.contains(task.id)

        HStack(alignment: .center, spacing: 8) {
            // Leading selection checkbox
            checkboxView(isSelected: isSelected)

            // Compact file format badge squircle
            fileFormatBadge

            // Filename and verification indicator
            filenameView

            Spacer(minLength: 12)

            // Inline mini progress bar
            if showProgressBar {
                miniProgressBar
            }

            // Metrics / Status text
            statusAndMetricsView
                .frame(minWidth: 120, alignment: .trailing)

            // Trailing compact action buttons
            compactActionButtons
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    reduceTransparency
                        ? (isSelected ? Theme.cardActive : (isHovered ? Theme.cardHover : Color(NSColor.windowBackgroundColor)))
                        : (isSelected ? Theme.cardActive : (isHovered ? Theme.cardHover : Theme.cardBackground))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? Theme.cardBorderActive : Theme.cardBorder, lineWidth: isSelected ? 1.5 : 1.0)
        }
        .overlay(alignment: .top) {
            if !isSelected && !reduceTransparency {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                    .frame(height: 10)
                    .clipped()
            }
        }
        .shadow(
            color: isSelected ? Theme.accent.opacity(0.16) : Color.black.opacity(0.04),
            radius: isSelected ? 6 : 3,
            x: 0,
            y: 1.5
        )
        .onHover { isHovered = $0 }
        .modifier(DragCompletedModifier(task: task))
    }

    // MARK: - Subviews

    private func checkboxView(isSelected: Bool) -> some View {
        Button {
            appState.toggleSelection(id: task.id)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Theme.cardBorder.opacity(2.0), lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(isSelected ? Theme.accent : Color.white.opacity(0.001))
                    )
                    .frame(width: 14, height: 14)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(isSelected ? "Deselect" : "Select")
        .accessibilityLabel(isSelected ? "Deselect \(task.filename)" : "Select \(task.filename)")
        .accessibilityValue(isSelected ? "Selected" : "Unselected")
    }

    private var fileFormatBadge: some View {
        let ext = (task.filename as NSString).pathExtension
        let style = Theme.fileBadge(for: ext)

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.gradientTop, style.gradientBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(style.borderColor, lineWidth: 0.8)
                )

            Image(systemName: style.systemIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(style.tintColor)
        }
        .frame(width: 24, height: 24)
        .help(style.label)
    }

    private var filenameView: some View {
        HStack(spacing: 5) {
            Text(task.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(task.filename)

            if task.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .help("Integrity Verified")
            }
        }
    }

    private var showProgressBar: Bool {
        switch task.status {
        case .downloading, .probing, .paused:
            return true
        case .completed, .failed, .idle:
            return false
        }
    }

    private var miniProgressBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.canvasBackground)
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
                .frame(width: 70, height: 4)

            let fillRatio = max(0.0, min(1.0, task.progress))
            let fillWidth = max(0.0, min(70.0, 70.0 * CGFloat(fillRatio)))

            Capsule()
                .fill(progressGradient)
                .frame(width: fillWidth, height: 4)
                .animation(.linear(duration: 0.25), value: task.progress)
        }
        .frame(width: 70, height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
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

    private var statusAndMetricsView: some View {
        Group {
            switch task.status {
            case .downloading:
                HStack(spacing: 4) {
                    Text(AppState.formatSpeed(task.bytesPerSecond))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.success)
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(Int(task.progress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
            case .probing:
                Text("Probing...")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.purple)
            case .paused:
                Text("Paused (\(Int(task.progress * 100))%)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.warning)
            case .completed:
                let size = AppState.formatBytes(task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes)
                Text("Completed • \(size)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            case .failed(let reason):
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Failed")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.critical)
                .help(reason)
            case .idle:
                Text("Queued")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactPrimaryActionHelpText: String {
        if task.status == .downloading || task.status == .probing {
            return "Pause Download"
        } else if task.status == .completed {
            return "Open File"
        } else {
            return "Resume Download"
        }
    }

    private var compactActionButtons: some View {
        HStack(spacing: 3) {
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
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                    } else if task.status == .completed {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActionHovered ? Theme.tagBackground : Color.white.opacity(0.001))
                )
                .contentShape(Rectangle())
            }
            .id("compact-action-\(task.id)")
            .buttonStyle(.tactile)
            .contentShape(Rectangle())
            .onHover { isActionHovered = $0 }
            .help(compactPrimaryActionHelpText)

            // Show in Finder button
            Button {
                appState.openInFinder(task: task)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isFinderHovered ? Theme.tagBackground : Color.white.opacity(0.001))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.tactile)
            .contentShape(Rectangle())
            .onHover { isFinderHovered = $0 }
            .help("Show in Finder")

            // More ellipsis Menu (Copy Link, Remove, Delete)
            Menu {
                queuePositionMenu
                Divider()
                Button("Copy Download Link") {
                    appState.copyDownloadLink(task: task)
                }
                Divider()
                Button("Remove from List") {
                    appState.remove(id: task.id, deleteFile: false)
                }
                Button("Delete File from Disk...", role: .destructive) {
                    appState.promptDelete(task: task)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isMoreHovered ? Theme.tagBackground : Color.white.opacity(0.001))
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .contentShape(Rectangle())
            .onHover { isMoreHovered = $0 }
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
                appState.moveTaskToTop(id: task.id)
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            .disabled(isFirst)

            Button {
                appState.moveTaskUp(id: task.id)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(isFirst)

            Button {
                appState.moveTaskDown(id: task.id)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(isLast)

            Button {
                appState.moveTaskToBottom(id: task.id)
            } label: {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
            .disabled(isLast)
        } label: {
            Label("Queue Position", systemImage: "arrow.up.arrow.down")
        }
    }
}
