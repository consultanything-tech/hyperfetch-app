//
//  QuickAddHUDView.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import SwiftUI
import DownloadKit

/// Floating HUD notification card presenting detected downloads with quick-action controls.
public struct QuickAddHUDView: View {
    public let url: URL
    public let filename: String
    public let onDownloadNow: () -> Void
    public let onCustomize: () -> Void
    public let onDismiss: () -> Void

    @ViewState private var isHovering: Bool = false

    public init(
        url: URL,
        filename: String,
        onDownloadNow: @escaping () -> Void,
        onCustomize: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.url = url
        self.filename = filename
        self.onDownloadNow = onDownloadNow
        self.onCustomize = onCustomize
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: App Logo, Title, and Close Button
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)

                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Download Detected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(url.host ?? "HyperFetch")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }

            // Filename preview and extension badge
            HStack(spacing: 10) {
                Image(systemName: categoryIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(categoryColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(url.absoluteString)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            // Action Buttons
            HStack(spacing: 8) {
                Button {
                    onCustomize()
                } label: {
                    Text("Customize...")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    onDownloadNow()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download Now")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var categoryIcon: String {
        let category = DownloadCategory.category(for: filename)
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
            return "arrow.down.circle.fill"
        }
    }

    private var categoryColor: Color {
        let category = DownloadCategory.category(for: filename)
        switch category {
        case .applications:
            return .blue
        case .archives:
            return .orange
        case .documents:
            return .red
        case .video:
            return .purple
        case .music:
            return .pink
        case .other, .all:
            return .cyan
        }
    }
}
