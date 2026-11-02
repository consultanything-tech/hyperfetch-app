//
//  SidebarView.swift
//  SwiftFlowApp
//

import SwiftUI
import DownloadKit

/// Sidebar navigation view organizing downloads by lifecycle status and file categories.
public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        List {
            // Status Filters Section
            Section("Downloads") {
                ForEach(StatusFilter.allCases) { filter in
                    NavigationLink(
                        value: filter,
                        label: {
                            HStack {
                                Label(filter.rawValue, systemImage: filter.iconName)
                                    .foregroundStyle(statusColor(for: filter))

                                Spacer()

                                Text("\(appState.count(for: filter))")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                    )
                }
            }

            // Categories Section
            Section("Categories") {
                ForEach(contentCategories, id: \.self) { category in
                    HStack {
                        Label {
                            Text(category.rawValue)
                        } icon: {
                            Image(systemName: iconName(for: category))
                                .foregroundStyle(color(for: category))
                        }

                        Spacer()

                        Text("\(appState.count(for: category))")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(appState.selectedCategory == category ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .onTapGesture {
                        if appState.selectedCategory == category {
                            appState.selectedCategory = nil
                        } else {
                            appState.selectedCategory = category
                        }
                    }
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
        VStack(spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: appState.activeDownloadCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(appState.activeDownloadCount > 0 ? Color.blue : Color.secondary)
                    .imageScale(.medium)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.formattedTotalSpeed)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("\(appState.activeDownloadCount) active downloads")
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
