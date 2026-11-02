//
//  DownloadRowView.swift
//  SwiftFlowApp
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DownloadKit

/// Single row item representing a download task in the list.
public struct DownloadRowView: View {
    public let task: DownloadTaskModel
    @EnvironmentObject private var appState: AppState
    @ViewState private var isMoreHovered: Bool = false

    public init(task: DownloadTaskModel) {
        self.task = task
    }

    public var body: some View {
        let isSelected = (appState.selectedTaskId == task.id)

        HStack(spacing: 12) {
            // File Icon
            fileTypeIcon
                .frame(width: 38, height: 38)

            // Details and Progress
            VStack(alignment: .leading, spacing: 4) {
                // Filename and percentage
                HStack {
                    Text(task.filename)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    statusTrailingBadge(isSelected: isSelected)
                }

                // Custom smooth Capsule progress bar
                customProgressBar(isSelected: isSelected)

                // Subtitle metadata
                statusMetadataView(isSelected: isSelected)
            }

            // Quick Actions
            quickActionButtons(isSelected: isSelected)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private var fileTypeIcon: some View {
        let ext = (task.filename as NSString).pathExtension
        let utType = UTType(filenameExtension: ext) ?? .data
        let image = NSWorkspace.shared.icon(for: utType)
        return Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private func customProgressBar(isSelected: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.16))
                    .frame(height: 6)

                // Progress fill
                let fillWidth = max(0.0, min(1.0, task.progress)) * geo.size.width
                Capsule()
                    .fill(progressGradient(isSelected: isSelected))
                    .frame(width: fillWidth, height: 6)
                    .animation(.linear(duration: 0.25), value: task.progress)
            }
        }
        .frame(height: 6)
    }

    private func progressGradient(isSelected: Bool) -> LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [Color.white, Color(red: 0.85, green: 0.95, blue: 1.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        switch task.status {
        case .downloading:
            return LinearGradient(
                colors: [Color.blue, Color(red: 0.15, green: 0.70, blue: 1.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .probing:
            return LinearGradient(
                colors: [Color.purple, Color(red: 0.70, green: 0.40, blue: 1.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .completed:
            return LinearGradient(
                colors: [Color.green, Color(red: 0.30, green: 0.85, blue: 0.50)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .paused:
            return LinearGradient(
                colors: [Color.orange, Color.yellow],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .failed:
            return LinearGradient(
                colors: [Color.red, Color.pink],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .idle:
            return LinearGradient(
                colors: [Color.secondary, Color.gray],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    @ViewBuilder
    private func statusTrailingBadge(isSelected: Bool) -> some View {
        if isSelected {
            switch task.status {
            case .downloading:
                Text("\(Int(task.progress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.25), in: Capsule())
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
            case .paused:
                Text("PAUSED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.25), in: Capsule())
            case .failed:
                Text("FAILED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.25), in: Capsule())
            case .probing:
                Text("PROBING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.25), in: Capsule())
            case .idle:
                Text("QUEUED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.25), in: Capsule())
            }
        } else {
            switch task.status {
            case .downloading:
                Text("\(Int(task.progress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .paused:
                Text("PAUSED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            case .failed:
                Text("FAILED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12), in: Capsule())
            case .probing:
                Text("PROBING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12), in: Capsule())
            case .idle:
                Text("QUEUED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func statusMetadataView(isSelected: Bool) -> some View {
        let baseColor = isSelected ? Color.white.opacity(0.85) : Color.secondary
        switch task.status {
        case .downloading:
            HStack(spacing: 6) {
                Text("\(AppState.formatBytes(task.downloadedBytes)) of \(AppState.formatBytes(task.totalBytes))")
                    .monospacedDigit()
                Text("•")
                Text(AppState.formatSpeed(task.bytesPerSecond))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text("•")
                let remaining = max(0, task.totalBytes - task.downloadedBytes)
                Text(AppState.formatETA(remainingBytes: remaining, bytesPerSecond: task.bytesPerSecond))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(baseColor)

        case .probing:
            Text("Connecting to server and negotiating HTTP Range...")
                .font(.caption)
                .foregroundStyle(baseColor)

        case .paused:
            HStack(spacing: 6) {
                Text("Paused")
                if task.totalBytes > 0 {
                    Text("•")
                    Text("\(AppState.formatBytes(task.downloadedBytes)) of \(AppState.formatBytes(task.totalBytes))")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(baseColor)

        case .completed:
            HStack(spacing: 6) {
                Text("Completed")
                Text("•")
                Text(AppState.formatBytes(task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes))
                    .monospacedDigit()
                if let completedAt = task.completedAt {
                    Text("•")
                    Text(completedAt, style: .date)
                }
            }
            .font(.caption)
            .foregroundStyle(baseColor)

        case .failed(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white : Color.red)

        case .idle:
            Text("Waiting in queue...")
                .font(.caption)
                .foregroundStyle(baseColor)
        }
    }

    private func quickActionButtons(isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            switch task.status {
            case .downloading, .probing:
                QuickActionButton(
                    icon: "pause.fill",
                    help: "Pause Download",
                    isSelected: isSelected
                ) {
                    appState.pause(id: task.id)
                }

            case .paused, .idle, .failed:
                QuickActionButton(
                    icon: "play.fill",
                    help: "Resume Download",
                    isSelected: isSelected
                ) {
                    appState.resume(id: task.id)
                }

            case .completed:
                QuickActionButton(
                    icon: "arrow.up.forward.app",
                    help: "Open File",
                    isSelected: isSelected
                ) {
                    appState.openFile(task: task)
                }
            }

            QuickActionButton(
                icon: "folder",
                help: "Show in Finder",
                isSelected: isSelected
            ) {
                appState.openInFinder(task: task)
            }

            Menu {
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isMoreHovered ? (isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15)) : Color.clear)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .onHover { isMoreHovered = $0 }
            .help("More Options")
        }
    }
}

private struct QuickActionButton: View {
    let icon: String
    let help: String
    let isSelected: Bool
    let action: () -> Void
    @ViewState private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? (isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15)) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}
