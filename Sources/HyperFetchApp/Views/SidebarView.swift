//
//  SidebarView.swift
//  HyperFetchApp
//

import SwiftUI
import DownloadKit

/// Sidebar navigation view organizing downloads by lifecycle status and file categories.
public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @ViewState private var isPulsing: Bool = false

    public init() {}

    public var body: some View {
        List(selection: $appState.sidebarSelection) {
            // Status Filters Section
            Section("Downloads") {
                ForEach(StatusFilter.allCases) { filter in
                    let item = SidebarItem.status(filter)
                    let isSelected = (appState.sidebarSelection == item)
                    HStack {
                        Label {
                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        } icon: {
                            Image(systemName: filter.iconName)
                                .foregroundStyle(statusColor(for: filter))
                        }

                        Spacer()

                        Text("\(appState.count(for: filter))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.12))
                            )
                    }
                    .tag(item)
                }
            }

            // Categories Section
            Section("Categories") {
                ForEach(contentCategories, id: \.self) { category in
                    let item = SidebarItem.category(category)
                    let isSelected = (appState.sidebarSelection == item)
                    HStack {
                        Label {
                            Text(category.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        } icon: {
                            Image(systemName: iconName(for: category))
                                .foregroundStyle(color(for: category))
                        }

                        Spacer()

                        Text("\(appState.count(for: category))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.12))
                            )
                    }
                    .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            bandwidthFootnote
        }
    }

    // MARK: - Helpers & Subviews

    private var contentCategories: [DownloadCategory] {
        DownloadCategory.allCases.filter { $0 != .all }
    }

    private var bandwidthFootnote: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                // Live pulsing mini indicator dot when downloads are active
                ZStack {
                    if appState.activeDownloadCount > 0 {
                        Circle()
                            .fill(Color.blue.opacity(0.35))
                            .frame(width: 14, height: 14)
                            .scaleEffect(isPulsing ? 1.5 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.8)
                            .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: isPulsing)

                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 16, height: 16)
                .onAppear {
                    isPulsing = true
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.formattedTotalSpeed)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(appState.activeDownloadCount > 0
                         ? "\(appState.activeDownloadCount) active download\(appState.activeDownloadCount == 1 ? "" : "s")"
                         : "All downloads idle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if appState.speedLimitPreset != .unlimited {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundStyle(.orange)
                        .help("Speed limited to \(appState.speedLimitPreset.rawValue)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func statusColor(for filter: StatusFilter) -> Color {
        switch filter {
        case .all:
            return .primary
        case .active:
            return .blue
        case .completed:
            return .green
        case .paused:
            return .orange
        case .failed:
            return .red
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
            return .primary
        case .archives:
            return .orange
        case .documents:
            return .blue
        case .video:
            return .purple
        case .music:
            return .pink
        case .applications:
            return .indigo
        case .other:
            return .gray
        }
    }
}
