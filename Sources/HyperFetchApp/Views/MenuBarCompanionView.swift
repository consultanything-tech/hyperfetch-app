//
//  MenuBarCompanionView.swift
//  HyperFetchApp
//
//  Rich interactive menu bar companion window popover for monitoring and controlling downloads.
//

import AppKit
import SwiftUI
import DownloadKit

/// Interactive companion popover view displayed from macOS status bar / menu bar.
public struct MenuBarCompanionView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .overlay(Theme.separator)

            if appState.tasks.isEmpty {
                emptyStateView
            } else {
                bodyTasksView
            }

            footerView
        }
        .frame(width: 340)
        .background(Theme.windowSurface)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                // Left: HyperFetch bolt icon + "HyperFetch" title
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x1C92FF), Color(hex: 0x006CE4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 22, height: 22)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text("HyperFetch")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }

                Spacer()

                // Right: Active download count badge ("X Active") and formatted total speed ("↓ X MB/s")
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.activeDownloadCount > 0 ? Theme.success : Theme.textTertiary.opacity(0.5))
                            .frame(width: 5, height: 5)
                        Text("\(appState.activeDownloadCount) Active")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appState.activeDownloadCount > 0 ? Theme.success : Theme.textTertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        appState.activeDownloadCount > 0 ? Theme.success.opacity(0.12) : Theme.tagBackground,
                        in: Capsule()
                    )

                    Text("↓ \(appState.formattedTotalSpeed)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(appState.totalDownloadSpeed > 0 ? Theme.accent : Theme.textTertiary)
                }
            }

            // Mini bandwidth sparkline: 8 vertical bars
            sparklineView
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var sparklineView: some View {
        let maxSpeed = max(1024 * 512, (appState.speedHistory.max() ?? 0))
        let isActive = appState.activeDownloadCount > 0

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                let speed = i < appState.speedHistory.count ? appState.speedHistory[i] : 0.0
                let normalized = isActive ? CGFloat(min(1.0, max(0.15, speed / maxSpeed))) : 0.15

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isActive && speed > 0
                            ? LinearGradient(
                                colors: [Color.blue.opacity(0.5 + Double(i) * 0.06), Theme.accent],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            : LinearGradient(
                                colors: [Theme.textTertiary.opacity(0.2), Theme.textTertiary.opacity(0.25)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 18 * normalized))
                    .animation(.easeInOut(duration: 0.25), value: normalized)
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Theme.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.textTertiary)

            Text("No Downloads")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            Button {
                MainWindowDelegate.shared.reopenMainWindow()
                appState.isAddDownloadSheetPresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add Download")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x1C92FF), Color(hex: 0x006CE4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.tactile)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Task List

    private var prioritizedTasks: [DownloadTaskModel] {
        let downloadingOrProbing = appState.tasks.filter { $0.status == .downloading || $0.status == .probing }
        let paused = appState.tasks.filter { $0.status == .paused }
        let other = appState.tasks.filter { $0.status != .downloading && $0.status != .probing && $0.status != .paused }
        let combined = downloadingOrProbing + paused + other
        return Array(combined.prefix(4))
    }

    private var bodyTasksView: some View {
        VStack(spacing: 6) {
            ForEach(prioritizedTasks) { task in
                taskRowView(for: task)
            }

            if appState.tasks.count > 4 {
                Text("+ \(appState.tasks.count - 4) more in HyperFetch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func taskRowView(for task: DownloadTaskModel) -> some View {
        let ext = (task.filename as NSString).pathExtension
        let badge = Theme.fileBadge(for: ext)

        return HStack(alignment: .center, spacing: 9) {
            // Category icon / file icon
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [badge.gradientTop, badge.gradientBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(badge.borderColor, lineWidth: 0.8)
                    )

                Image(systemName: badge.systemIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(badge.tintColor)
            }
            .frame(width: 26, height: 26)

            // Filename + Linear progress bar + Status text
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.filename)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                }

                // Linear progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.inputBackground)
                            .overlay(
                                Capsule()
                                    .stroke(Theme.cardBorder, lineWidth: 0.8)
                            )
                        Capsule()
                            .fill(taskProgressGradient(for: task.status))
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(max(0.0, min(1.0, task.progress))))))
                    }
                }
                .frame(height: 4)

                // Status text (progress % and speed)
                HStack(spacing: 4) {
                    Text("\(Int(task.progress * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)

                    Text("•")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textTertiary)

                    if task.status == .downloading && task.bytesPerSecond > 0 {
                        Text(AppState.formatSpeed(task.bytesPerSecond))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text(taskStatusTitle(for: task.status))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(taskStatusColor(for: task.status))
                    }

                    Spacer()
                }
            }

            // Play/Pause tactile button
            taskActionButton(for: task)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func taskActionButton(for task: DownloadTaskModel) -> some View {
        switch task.status {
        case .downloading, .probing:
            Button {
                appState.pause(id: task.id)
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Pause Download")

        case .paused, .idle:
            Button {
                appState.resume(id: task.id)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Resume Download")

        case .failed:
            Button {
                appState.resume(id: task.id)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.warning)
                    .frame(width: 22, height: 22)
                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Retry Download")

        case .completed:
            Button {
                appState.openInFinder(task: task)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Show in Finder")
        }
    }

    private func taskStatusTitle(for status: DownloadStatus) -> String {
        switch status {
        case .downloading: return "Downloading"
        case .probing: return "Probing…"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .idle: return "Queued"
        }
    }

    private func taskStatusColor(for status: DownloadStatus) -> Color {
        switch status {
        case .downloading: return Theme.accent
        case .probing: return Color.purple
        case .paused: return Theme.warning
        case .completed: return Theme.success
        case .failed: return Theme.critical
        case .idle: return Theme.textTertiary
        }
    }

    private func taskProgressGradient(for status: DownloadStatus) -> LinearGradient {
        switch status {
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

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            Divider()
                .overlay(Theme.separator)

            footerRow1

            Divider()
                .overlay(Theme.separator)

            footerRow2
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var footerRow1: some View {
        HStack(spacing: 8) {
            Button {
                appState.pauseAll()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                    Text("Pause All")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(appState.activeDownloadCount > 0 ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .disabled(appState.activeDownloadCount == 0)

            Button {
                appState.resumeAll()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                    Text("Resume All")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(appState.pausedDownloadCount > 0 ? Theme.accent : Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .disabled(appState.pausedDownloadCount == 0)

            Spacer()

            if appState.hasCompletedTasks {
                Button {
                    appState.clearCompletedTasks()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Clear Finished")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.tactile)
            }
        }
    }

    private var footerRow2: some View {
        HStack(spacing: 6) {
            Button {
                MainWindowDelegate.shared.reopenMainWindow()
                appState.isAddDownloadSheetPresented = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add Download")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Add New Download")

            Button {
                MainWindowDelegate.shared.reopenMainWindow()
            } label: {
                Text("Open HyperFetch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Open HyperFetch Window")

            Spacer()

            Button {
                appState.openSettingsWindow(tab: .general)
            } label: {
                Text("Settings...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Settings...")

            Button {
                MainWindowDelegate.shared.isTerminating = true
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Theme.critical.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.tactile)
            .help("Quit HyperFetch")
        }
    }
}
