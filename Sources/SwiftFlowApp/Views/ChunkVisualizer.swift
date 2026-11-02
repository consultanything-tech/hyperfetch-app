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
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Connection Segments", systemImage: "square.split.3x1.fill")
                    .font(.headline)

                Spacer()

                if !task.chunks.isEmpty {
                    Text("\(completedChunkCount)/\(task.chunks.count) completed")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            if task.chunks.isEmpty {
                // Pending allocation state
                HStack(spacing: 10) {
                    Image(systemName: "circle.dotted")
                        .font(.title3)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(task.chunks) { chunk in
                    chunkStripBlock(chunk)
                }
            }
            .frame(height: 32)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .green, label: "Completed")
                legendItem(color: .blue, label: "Downloading")
                legendItem(color: .secondary.opacity(0.4), label: "Pending")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
        }
    }

    private func chunkStripBlock(_ chunk: Chunk) -> some View {
        GeometryReader { geo in
            let blockWidth = geo.size.width
            let progressRatio = CGFloat(max(0.0, min(1.0, chunk.progress)))

            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))

                // Progress fill
                Rectangle()
                    .fill(chunkGradient(chunk))
                    .frame(width: blockWidth * progressRatio)
                    .animation(.linear(duration: 0.25), value: chunk.progress)

                // Label overlay: adapt gracefully to narrow widths (prevents overflow on 8/16 chunks)
                if blockWidth >= 64 {
                    // Wide block: show chunk number and percentage
                    HStack {
                        Text("#\(chunk.index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(progressRatio > 0.4 ? Color.white : Color.primary)
                        Spacer()
                        Text("\(Int(chunk.progress * 100))%")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(progressRatio > 0.4 ? Color.white : Color.secondary)
                    }
                    .padding(.horizontal, 4)
                } else if blockWidth >= 34 {
                    // Medium block: show only chunk number centered
                    HStack {
                        Spacer()
                        Text("#\(chunk.index + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(progressRatio > 0.4 ? Color.white : Color.primary)
                        Spacer()
                    }
                }
                // When blockWidth < 34: render clean colored bar without text to prevent clipping/overflow
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help("Chunk #\(chunk.index + 1): \(Int(chunk.progress * 100))% • \(chunkStatusTitle(chunk))")
    }

    private func singleChunkBar(_ chunk: Chunk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color(red: 0.2, green: 0.7, blue: 1.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, task.progress))), height: 8)
                        .animation(.linear(duration: 0.25), value: task.progress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Connection 1 of 1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(AppState.formatBytes(task.downloadedBytes)) downloaded")
                    .font(.caption2)
                    .monospacedDigit()
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
                        .background(chunkColor(chunk).opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(chunkColor(chunk))

                    // Progress Mini Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: 5)

                            Capsule()
                                .fill(chunkGradient(chunk))
                                .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, chunk.progress))), height: 5)
                                .animation(.linear(duration: 0.25), value: chunk.progress)
                        }
                    }
                    .frame(width: 80, height: 5)

                    // Bytes downloaded / expected
                    Text(chunkBytesDescription(chunk))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Status Pill
                    Text(chunkStatusTitle(chunk))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(chunkColor(chunk))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(chunkColor(chunk).opacity(0.12), in: Capsule())
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                )
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

    private func chunkGradient(_ chunk: Chunk) -> LinearGradient {
        switch chunk.status {
        case .completed:
            return LinearGradient(
                colors: [Color.green, Color(red: 0.35, green: 0.85, blue: 0.55)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .downloading:
            return LinearGradient(
                colors: [Color.blue, Color(red: 0.25, green: 0.75, blue: 1.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .failed:
            return LinearGradient(
                colors: [Color.red, Color.pink],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .pending:
            if chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength {
                return LinearGradient(
                    colors: [Color.green, Color(red: 0.35, green: 0.85, blue: 0.55)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            return LinearGradient(
                colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.5)],
                startPoint: .leading,
                endPoint: .trailing
            )
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
