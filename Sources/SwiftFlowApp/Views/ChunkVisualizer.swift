//
//  ChunkVisualizer.swift
//  SwiftFlowApp
//

import SwiftUI
import DownloadKit

/// Displays the segmented multi-chunk download visualizer inspired by Free Download Manager.
public struct ChunkVisualizer: View {
    public let task: DownloadTaskModel

    public init(task: DownloadTaskModel) {
        self.task = task
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Connection Segments", systemImage: "square.split.3x1.fill")
                    .font(.headline)

                Spacer()

                if !task.chunks.isEmpty {
                    Text("\(completedChunkCount)/\(task.chunks.count) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            if task.chunks.isEmpty {
                // Pending allocation state
                HStack {
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.secondary)
                    Text("Connection segments will be allocated once probing completes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else if !task.supportsRange {
                // Single stream warning banner
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Single Connection Mode")
                            .font(.subheadline.bold())
                        Text("The remote server does not advertise HTTP Range support; downloading via single stream.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                // Single chunk bar
                if let firstChunk = task.chunks.first {
                    singleChunkBar(firstChunk)
                }
            } else {
                // Multi-chunk segmented strip
                segmentedStripView

                // Detailed chunk list
                chunkBreakdownList
            }
        }
    }

    // MARK: - Subviews

    private var completedChunkCount: Int {
        task.chunks.filter { $0.status == .completed || ($0.expectedLength > 0 && $0.bytesDownloaded >= $0.expectedLength) }.count
    }

    private var segmentedStripView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(task.chunks) { chunk in
                    chunkStripBlock(chunk)
                }
            }
            .frame(height: 34)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Legend
            HStack(spacing: 14) {
                legendItem(color: .green, label: "Completed")
                legendItem(color: .blue, label: "Downloading")
                legendItem(color: .secondary.opacity(0.4), label: "Pending")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func chunkStripBlock(_ chunk: Chunk) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))

                // Progress fill
                Rectangle()
                    .fill(chunkColor(chunk))
                    .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, chunk.progress))))
                    .animation(.linear(duration: 0.2), value: chunk.progress)

                // Label overlay
                HStack {
                    Text("#\(chunk.index + 1)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(chunk.progress > 0.5 ? Color.white : Color.primary)
                    Spacer()
                    if geo.size.width > 55 {
                        Text("\(Int(chunk.progress * 100))%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(chunk.progress > 0.5 ? Color.white : Color.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func singleChunkBar(_ chunk: Chunk) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .tint(.blue)

            HStack {
                Text("Connection 1 of 1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(AppState.formatBytes(task.downloadedBytes)) downloaded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chunkBreakdownList: some View {
        VStack(spacing: 6) {
            ForEach(task.chunks) { chunk in
                HStack(spacing: 12) {
                    // Chunk Index Badge
                    Text("#\(chunk.index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(chunkColor(chunk).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(chunkColor(chunk))

                    // Progress Mini Bar
                    ProgressView(value: chunk.progress)
                        .progressViewStyle(.linear)
                        .tint(chunkColor(chunk))
                        .frame(width: 80)

                    // Bytes downloaded / expected
                    Text(chunkBytesDescription(chunk))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Status Pill
                    Text(chunkStatusTitle(chunk))
                        .font(.caption2.bold())
                        .foregroundStyle(chunkColor(chunk))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
    }

    private func chunkColor(_ chunk: Chunk) -> Color {
        switch chunk.status {
        case .completed:
            return .green
        case .downloading:
            return .blue
        case .failed:
            return .red
        case .pending:
            if chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength {
                return .green
            }
            return .secondary.opacity(0.4)
        }
    }

    private func chunkStatusTitle(_ chunk: Chunk) -> String {
        switch chunk.status {
        case .completed:
            return "Done"
        case .downloading:
            return "Active"
        case .failed:
            return "Failed"
        case .pending:
            if chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength {
                return "Done"
            }
            return "Pending"
        }
    }

    private func chunkBytesDescription(_ chunk: Chunk) -> String {
        if chunk.expectedLength > 0 {
            let downloaded = AppState.formatBytes(chunk.bytesDownloaded)
            let total = AppState.formatBytes(chunk.expectedLength)
            return "\(downloaded) / \(total)"
        } else {
            return "\(AppState.formatBytes(chunk.bytesDownloaded))"
        }
    }
}
