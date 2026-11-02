//
//  ChunkVisualizer.swift
//  HyperFetchApp
//
//  Modernized connection segments visualization matching the Obsidian Sequoia design.
//

import SwiftUI
import DownloadKit

/// Displays the segmented multi-chunk download visualizer and per-thread telemetry.
public struct ChunkVisualizer: View {
    public let task: DownloadTaskModel

    public init(task: DownloadTaskModel) {
        self.task = task
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)

                    Text("Connection Segments")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                if !task.chunks.isEmpty {
                    Text("\(completedChunkCount)/\(task.chunks.count) completed")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Theme.accent.opacity(0.25), lineWidth: 0.8)
                        )
                }
            }

            if task.chunks.isEmpty {
                // Pending allocation state
                HStack(spacing: 10) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Connection segments will be allocated once server handshake completes.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
            } else if !task.supportsRange {
                // Single stream banner
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Single Connection Mode")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Server does not advertise byte-range support; downloading via single stream.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                        .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
                )

                if let firstChunk = task.chunks.first {
                    singleChunkProgressCard(firstChunk)
                }
            } else {
                // Legend
                legendView

                // Visual Segments Heat Blocks Grid
                chunkHeatBlocksGrid

                // Granular Breakdown per Thread
                threadBreakdownList
            }
        }
    }

    // MARK: - Subviews

    private var completedChunkCount: Int {
        task.chunks.filter { $0.status == .completed || ($0.expectedLength > 0 && $0.bytesDownloaded >= $0.expectedLength) }.count
    }

    private var legendView: some View {
        HStack(spacing: 16) {
            legendItem(color: Theme.success, label: "Completed")
            legendItem(color: Theme.accent, label: "Downloading")
            legendItem(color: Theme.textTertiary.opacity(0.5), label: "Pending")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 2)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
        }
    }

    /// Heat map grid of chunk segment blocks (#1 to #N)
    private var chunkHeatBlocksGrid: some View {
        let chunkCount = max(1, task.chunks.count)
        let columns = min(8, max(4, chunkCount))

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns),
            spacing: 6
        ) {
            ForEach(task.chunks) { chunk in
                chunkHeatBlock(chunk)
            }
        }
        .padding(8)
        .background(Theme.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func chunkHeatBlock(_ chunk: Chunk) -> some View {
        let isDone = chunk.status == .completed || (chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength)
        let isActive = (chunk.status == .downloading)

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDone ? Theme.success : (isActive ? Theme.accent : Theme.cardBackground))
                .frame(height: 34)

            if isActive {
                // Bottom pulsing progress highlight
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(height: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Text("#\(chunk.index + 1)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isDone ? Color(hex: 0x0b2812) : (isActive ? Color.white : Theme.textTertiary))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isDone ? Theme.success.opacity(0.5) : (isActive ? Theme.accent.opacity(0.5) : Theme.cardBorder), lineWidth: 1)
        )
        .help("Segment #\(chunk.index + 1): \(chunkStatusTitle(chunk)) (\(chunkBytesDescription(chunk)))")
    }

    /// Granular thread breakdown list
    private var threadBreakdownList: some View {
        VStack(spacing: 6) {
            ForEach(task.chunks) { chunk in
                chunkRowCard(chunk)
            }
        }
    }

    private func chunkRowCard(_ chunk: Chunk) -> some View {
        let isDone = chunk.status == .completed || (chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength)
        let isActive = (chunk.status == .downloading)

        return HStack(spacing: 10) {
            // Segment index tag
            Text("#\(chunk.index + 1)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isDone ? Theme.success : (isActive ? Theme.accent : Theme.textTertiary))
                .frame(width: 22, alignment: .leading)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.canvasBackground)
                        .frame(height: 5)

                    let progressRatio = max(0.0, min(1.0, CGFloat(chunk.progress)))
                    Capsule()
                        .fill(isDone ? Theme.success : (isActive ? Theme.accent : Theme.textTertiary.opacity(0.3)))
                        .frame(width: geo.size.width * progressRatio, height: 5)
                        .animation(.linear(duration: 0.2), value: chunk.progress)
                }
            }
            .frame(height: 5)

            // Byte progress description
            Text(chunkBytesDescription(chunk))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
                .frame(minWidth: 100, alignment: .trailing)

            // Status Badge
            Text(chunkStatusTitle(chunk))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isDone ? Theme.success : (isActive ? Theme.accent : Theme.textTertiary))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (isDone ? Theme.success : (isActive ? Theme.accent : Theme.textTertiary)).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke((isDone ? Theme.success : (isActive ? Theme.accent : Theme.cardBorder)).opacity(0.3), lineWidth: 0.8)
                )
                .frame(width: 50, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isActive ? Theme.accent.opacity(0.06) : Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Theme.accent.opacity(0.25) : Theme.cardBorder, lineWidth: 1)
        )
    }

    private func singleChunkProgressCard(_ chunk: Chunk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Stream #1")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(chunkBytesDescription(chunk))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.canvasBackground)
                        .frame(height: 6)

                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, chunk.progress))), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
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
