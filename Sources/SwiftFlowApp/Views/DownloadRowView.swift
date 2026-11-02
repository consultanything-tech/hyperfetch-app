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

    public init(task: DownloadTaskModel) {
        self.task = task
    }

    public var body: some View {
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
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    statusTrailingBadge
                }

                // Progress Bar
                progressBar

                // Subtitle metadata
                statusMetadataView
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Quick Actions
            quickActionButtons
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

    private var progressBar: some View {
        ProgressView(value: task.progress)
            .progressViewStyle(.linear)
            .tint(progressTint)
            .scaleEffect(x: 1, y: 1.2, anchor: .center)
    }

    private var progressTint: Color {
        switch task.status {
        case .downloading:
            return .blue
        case .probing:
            return .purple
        case .completed:
            return .green
        case .paused:
            return .orange
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var statusTrailingBadge: some View {
        Group {
            switch task.status {
            case .downloading:
                Text("\(Int(task.progress * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .paused:
                Text("PAUSED")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            case .failed:
                Text("FAILED")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
            case .probing:
                Text("PROBING")
                    .font(.caption2.bold())
                    .foregroundStyle(.purple)
            case .idle:
                Text("QUEUED")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusMetadataView: some View {
        switch task.status {
        case .downloading:
            HStack(spacing: 6) {
                Text("\(AppState.formatBytes(task.downloadedBytes)) of \(AppState.formatBytes(task.totalBytes))")
                Text("•")
                Text(AppState.formatSpeed(task.bytesPerSecond))
                    .foregroundStyle(.primary)
                Text("•")
                let remaining = max(0, task.totalBytes - task.downloadedBytes)
                Text(AppState.formatETA(remainingBytes: remaining, bytesPerSecond: task.bytesPerSecond))
            }

        case .probing:
            Text("Connecting to server and negotiating HTTP Range...")

        case .paused:
            HStack(spacing: 6) {
                Text("Paused")
                if task.totalBytes > 0 {
                    Text("•")
                    Text("\(AppState.formatBytes(task.downloadedBytes)) of \(AppState.formatBytes(task.totalBytes))")
                }
            }

        case .completed:
            HStack(spacing: 6) {
                Text("Completed")
                Text("•")
                Text(AppState.formatBytes(task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes))
                if let completedAt = task.completedAt {
                    Text("•")
                    Text(completedAt, style: .date)
                }
            }

        case .failed(let reason):
            Text(reason)
                .foregroundStyle(.red)

        case .idle:
            Text("Waiting in queue...")
        }
    }

    private var quickActionButtons: some View {
        HStack(spacing: 6) {
            switch task.status {
            case .downloading, .probing:
                Button {
                    appState.pause(id: task.id)
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(.borderless)
                .help("Pause Download")

            case .paused, .idle, .failed:
                Button {
                    appState.resume(id: task.id)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Resume Download")

            case .completed:
                Button {
                    appState.openFile(task: task)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open File")
            }

            Button {
                appState.openInFinder(task: task)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")

            Menu {
                Button("Copy Download Link") {
                    appState.copyDownloadLink(task: task)
                }
                Divider()
                Button("Remove from List") {
                    appState.remove(id: task.id, deleteFile: false)
                }
                Button("Delete File from Disk", role: .destructive) {
                    appState.remove(id: task.id, deleteFile: true)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
        }
    }
}
