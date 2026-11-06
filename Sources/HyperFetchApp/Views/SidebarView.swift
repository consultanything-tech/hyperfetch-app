//
//  SidebarView.swift
//  HyperFetchApp
//
//  Modernized sidebar navigation view organizing downloads by lifecycle status,
//  file categories, and featuring real-time bandwidth telemetry and engine status.
//

import SwiftUI
import DownloadKit

/// Sidebar navigation view organizing downloads by lifecycle status and file categories.
public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var versionManager: AppVersionManager

    @ViewState private var isPulsing: Bool = false

    public init() {}

    public var body: some View {
        List(selection: $appState.sidebarSelection) {
            transfersSection
            categoriesSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBackground)
        .safeAreaInset(edge: .bottom) {
            sidebarFooterTelemetry
        }
        .onAppear {
            isPulsing = true
        }
    }

    // MARK: - Transfers Section

    private var transfersSection: some View {
        Section("Transfers") {
            ForEach(StatusFilter.allCases) { filter in
                let item = SidebarItem.status(filter)
                let isSelected = (appState.sidebarSelection == item)
                let count = appState.count(for: filter)

                SidebarNavRow(
                    title: filter.rawValue,
                    icon: filter.iconName,
                    iconColor: statusColor(for: filter),
                    badgeText: "\(count)",
                    isSelected: isSelected,
                    isHighlightedBadge: filter == .all && isSelected
                )
                .tag(item)
            }
        }
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(contentCategories, id: \.self) { category in
                let item = SidebarItem.category(category)
                let isSelected = (appState.sidebarSelection == item)
                let count = appState.count(for: category)

                SidebarNavRow(
                    title: categoryTitle(for: category),
                    icon: iconName(for: category),
                    iconColor: color(for: category),
                    badgeText: "\(count)",
                    isSelected: isSelected,
                    isHighlightedBadge: false
                )
                .tag(item)
            }
        }
    }

    // MARK: - Sidebar Footer Telemetry

    private var sidebarFooterTelemetry: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Theme.separator)

            VStack(spacing: 10) {
                // Real-time Bandwidth Telemetry Card
                VStack(spacing: 8) {
                    // Header: Status dot + Title + Preset Badge
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.activeDownloadCount > 0 ? Theme.success : Theme.textTertiary.opacity(0.5))
                                .frame(width: 7, height: 7)

                            Text("Total Bandwidth")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        Text(bandwidthStatusTitle)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(appState.speedLimitPreset == .unlimited ? Theme.success : Theme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (appState.speedLimitPreset == .unlimited ? Theme.success : Theme.warning).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        (appState.speedLimitPreset == .unlimited ? Theme.success : Theme.warning).opacity(0.25),
                                        lineWidth: 0.8
                                    )
                            )
                    }

                    // Speed readout and active count
                    HStack(alignment: .firstTextBaseline) {
                        Text(appState.formattedTotalSpeed)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(appState.activeDownloadCount > 0 ? Theme.success : Theme.textTertiary)
                            Text("\(appState.activeDownloadCount) active")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    // Mini Sparkline Simulation (8 bars)
                    sparklineView
                        .frame(height: 22)

                    // Disk Status Line
                    HStack {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                        Text("Disk Storage:")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text(appState.availableDiskSpaceString)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.success)
                    }
                    .padding(.top, 2)
                    .overlay(alignment: .top) {
                        Divider()
                            .overlay(Theme.separator.opacity(0.5))
                    }
                }
                .padding(10)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                // Support HyperFetch (Ko-fi)
                Link(destination: URL(string: "https://ko-fi.com/consultanythingtech")!) {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.orange.opacity(0.18))
                                .frame(width: 26, height: 26)
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.orange)
                        }

                        VStack(alignment: .leading, spacing: 1.5) {
                            Text("Support HyperFetch")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Buy us a coffee on Ko-fi")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.orange.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Support HyperFetch development on Ko-fi")

                // Version & Update Check
                HStack {
                    Text("HyperFetch \(versionManager.fullVersionString)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)

                    Spacer()

                    Button {
                        versionManager.checkForUpdates(userInitiated: true)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Check for Updates")
                }
                .padding(.horizontal, 2)
            }
            .padding(12)
            .background(Theme.statusBarBackground)
        }
    }

    private var sparklineView: some View {
        let maxSpeed = max(1024 * 512, (appState.speedHistory.max() ?? 0))
        let isActive = appState.activeDownloadCount > 0

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<8, id: \.self) { i in
                let speed = i < appState.speedHistory.count ? appState.speedHistory[i] : 0.0
                let normalized = isActive ? CGFloat(min(1.0, max(0.12, speed / maxSpeed))) : 0.12

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
                    .frame(height: max(3, 22 * normalized))
                    .animation(.easeInOut(duration: 0.3), value: normalized)
            }
        }
    }

    private var bandwidthStatusTitle: String {
        if appState.speedLimitPreset == .unlimited {
            return "Optimal"
        } else {
            return appState.speedLimitPreset.rawValue
        }
    }

    // MARK: - Helpers

    private var contentCategories: [DownloadCategory] {
        DownloadCategory.allCases.filter { $0 != .all }
    }

    private func categoryTitle(for category: DownloadCategory) -> String {
        switch category {
        case .all:
            return "All"
        case .archives:
            return "Archives (.zip, .xip)"
        case .documents:
            return "Documents"
        case .video:
            return "Video & Media"
        case .music:
            return "Audio & Music"
        case .applications:
            return "Applications & Disk"
        case .other:
            return "Other"
        }
    }

    private func statusColor(for filter: StatusFilter) -> Color {
        switch filter {
        case .all:
            return Theme.accent
        case .active:
            return Color.cyan
        case .completed:
            return Theme.success
        case .paused:
            return Theme.warning
        case .failed:
            return Theme.critical
        }
    }

    private func iconName(for category: DownloadCategory) -> String {
        switch category {
        case .all:
            return "tray.full"
        case .archives:
            return "archivebox.fill"
        case .documents:
            return "doc.text.fill"
        case .video:
            return "film.fill"
        case .music:
            return "music.note"
        case .applications:
            return "app.fill"
        case .other:
            return "questionmark.folder.fill"
        }
    }

    private func color(for category: DownloadCategory) -> Color {
        switch category {
        case .all:
            return Theme.accent
        case .archives:
            return Theme.warning
        case .documents:
            return Theme.accent
        case .video:
            return Color.purple
        case .music:
            return Color.pink
        case .applications:
            return Color.indigo
        case .other:
            return Theme.textTertiary
        }
    }
}

// MARK: - SidebarNavRow Component

private struct SidebarNavRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    let badgeText: String
    let isSelected: Bool
    let isHighlightedBadge: Bool

    var body: some View {
        HStack(spacing: 8) {
            // 22x22 squircle icon container with colored tint / active accent
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Theme.accent : iconColor.opacity(0.15))
                    .frame(width: 22, height: 22)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : iconColor)
            }

            // Title in system font (weight .semibold when selected, .regular otherwise)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)

            Spacer()

            // Monospaced count pill badge in a capsule
            Text(badgeText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(badgeForeground)
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(badgeBackground, in: Capsule())
        }
        .padding(.vertical, 2)
    }

    private var badgeForeground: Color {
        if isSelected {
            return isHighlightedBadge ? Color.white : Theme.textPrimary
        }
        return Theme.textTertiary
    }

    private var badgeBackground: Color {
        if isSelected {
            return isHighlightedBadge ? Theme.accent : Theme.tagBackground
        }
        return Theme.tagBackground.opacity(0.8)
    }
}
