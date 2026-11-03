//
//  AboutView.swift
//  HyperFetchApp
//
//  Created by HyperFetch on 2026-11-02.
//

import AppKit
import SwiftUI

/// Dedicated About window/sheet displaying application branding, version, and direct update triggers.
public struct AboutView: View {
    @EnvironmentObject private var versionManager: AppVersionManager
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            // App Icon
            appIconView
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)

            // App Name & Tagline
            VStack(spacing: 4) {
                Text("HyperFetch")
                    .font(.title2.bold())

                Text("High-Speed Multi-Chunk Download Manager")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Version details
            Text("Version \(versionManager.currentVersion) (\(versionManager.buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

            // Check for updates button
            Button {
                versionManager.isAboutSheetPresented = false
                versionManager.checkForUpdates(userInitiated: true)
            } label: {
                Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()

            Divider()

            // Links and Copyright
            HStack(spacing: 14) {
                Link("GitHub Project", destination: URL(string: "https://github.com/consultanything-tech/hyperfetch")!)
                    .font(.caption)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Link("Release Notes", destination: URL(string: "https://github.com/consultanything-tech/hyperfetch/releases")!)
                    .font(.caption)

                Spacer()

                Button("Done") {
                    versionManager.isAboutSheetPresented = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(width: 380, height: 340)
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
}
