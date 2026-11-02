//
//  UpdateSheetView.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import SwiftUI

/// Modal sheet presenting update check progress, up-to-date confirmations, or available release details.
public struct UpdateSheetView: View {
    @EnvironmentObject private var versionManager: AppVersionManager
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // State Body
            VStack {
                switch versionManager.state {
                case .idle, .checking:
                    checkingView

                case .upToDate(let currentVersion, let lastChecked):
                    upToDateView(version: currentVersion, date: lastChecked)

                case .updateAvailable(let newVersion, let currentVersion, let notes, let downloadURL, _):
                    updateAvailableView(newVersion: newVersion, currentVersion: currentVersion, notes: notes, downloadURL: downloadURL)

                case .failed(let error):
                    failedView(error: error)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Footer / Actions
            footerView
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 460, height: 320)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            appIconView
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Software Update")
                    .font(.headline)

                Text("HyperFetch \(versionManager.fullVersionString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var appIconView: some View {
        Group {
            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "arrow.down.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - States

    private var checkingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Checking for updates...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func upToDateView(version: String, date: Date) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.green)

            Text("HyperFetch is up to date")
                .font(.title3.bold())

            Text("Version \(version) is currently the newest version available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Last checked: \(versionManager.formattedLastCheckedDate)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxHeight: .infinity)
    }

    private func updateAvailableView(newVersion: String, currentVersion: String, notes: String, downloadURL: URL?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("HyperFetch \(newVersion) is available")
                        .font(.headline)

                    Text("You have version \(currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let url = downloadURL {
                    Button("Download Update") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text("Release Notes:")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ScrollView {
                Text(notes)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 90)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxHeight: .infinity)
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Unable to Check for Updates")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                versionManager.checkForUpdates(userInitiated: true)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if versionManager.state != .checking {
                Button("Check Again") {
                    versionManager.checkForUpdates(userInitiated: true)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Close") {
                versionManager.isUpdateSheetPresented = false
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }
}
