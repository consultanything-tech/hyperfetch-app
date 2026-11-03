//
//  UpdateSheetView.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import SwiftUI
import DownloadKit

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

                case .downloading(let newVersion, let progress, let bytesDownloaded, let totalBytes):
                    downloadingView(newVersion: newVersion, progress: progress, bytesDownloaded: bytesDownloaded, totalBytes: totalBytes)

                case .extracting(let newVersion):
                    extractingView(newVersion: newVersion)

                case .readyToInstall(let newVersion, let stagedAppURL):
                    readyToInstallView(newVersion: newVersion, stagedAppURL: stagedAppURL)

                case .installing:
                    installingView

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
        .frame(width: 480, height: 340)
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
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Update Now") {
                            versionManager.downloadAndInstallUpdate(from: url, newVersion: newVersion)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Download manually from GitHub") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.link)
                        .font(.caption2)
                    }
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

    private func downloadingView(newVersion: String, progress: Double, bytesDownloaded: Int64, totalBytes: Int64) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.blue)

            Text("Downloading HyperFetch \(newVersion)...")
                .font(.headline)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)

            Text("Downloading update... \(ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) (\(Int(progress * 100))%)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                versionManager.cancelDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private func extractingView(newVersion: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Preparing update package...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func readyToInstallView(newVersion: String, stagedAppURL: URL) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)

            Text("Update Ready to Install")
                .font(.title3.bold())

            Text("HyperFetch \(newVersion) has been downloaded. Restart the application to apply the update.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button("Later") {
                    versionManager.isUpdateSheetPresented = false
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Restart and Install") {
                    versionManager.installAndRelaunch(stagedAppURL: stagedAppURL)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var installingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Installing update and relaunching...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Unable to Update")
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
            switch versionManager.state {
            case .idle, .upToDate, .failed:
                Button("Check Again") {
                    versionManager.checkForUpdates(userInitiated: true)
                }
                .buttonStyle(.bordered)
            default:
                EmptyView()
            }

            Spacer()

            if case .installing = versionManager.state {
                // In the middle of relaunching, no close button
            } else {
                Button("Close") {
                    versionManager.isUpdateSheetPresented = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}
