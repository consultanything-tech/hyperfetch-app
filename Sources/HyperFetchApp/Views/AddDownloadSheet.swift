//
//  AddDownloadSheet.swift
//  HyperFetchApp
//
//  Modernized macOS modal dialog for adding new downloads with multi-chunk acceleration.
//

import AppKit
import SwiftUI
import DownloadKit

/// Modal sheet for configuring and starting a new accelerated download.
public struct AddDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @FocusState private var isURLFocused: Bool
    @ViewState private var urlString: String = ""
    @ViewState private var customFilename: String = ""
    @ViewState private var destinationFolderURL: URL
    @ViewState private var chunkCount: Int = 4
    @ViewState private var autoStart: Bool = true
    @ViewState private var isAdvancedExpanded: Bool = false
    @ViewState private var customUserAgent: String = "HyperFetch/1.0 (macOS)"
    @ViewState private var sha256Checksum: String = ""

    private let chunkCountOptions = [1, 2, 4, 8, 16]

    public init() {
        let savedPath = UserDefaults.standard.string(forKey: "com.hyperfetch.defaultDownloadDirectory")
        let defaultDownloads: URL
        if let savedPath, !savedPath.isEmpty {
            defaultDownloads = URL(fileURLWithPath: savedPath)
        } else {
            defaultDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        }
        let savedChunks = UserDefaults.standard.integer(forKey: "com.hyperfetch.defaultChunkCount")
        let initialChunks = savedChunks > 0 ? savedChunks : 4

        _destinationFolderURL = ViewState(wrappedValue: defaultDownloads)
        _chunkCount = ViewState(wrappedValue: initialChunks)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Divider()
                .overlay(Theme.separator)
                .padding(.horizontal, 24)

            // MARK: - Form Body
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sourceURLSection
                    saveDestinationSection
                    filenameSection
                    accelerationChunksSection
                    optionsAndAdvancedSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            // MARK: - Footer
            footerView
        }
        .frame(width: 560)
        .background(Theme.windowSurface)
        .onAppear {
            chunkCount = appState.defaultChunkCount
            destinationFolderURL = appState.defaultDownloadDirectoryURL
            if !appState.prefilledURL.isEmpty {
                urlString = appState.prefilledURL
                appState.prefilledURL = ""
                if !appState.prefilledFilename.isEmpty {
                    customFilename = appState.prefilledFilename
                    appState.prefilledFilename = ""
                }
            } else {
                autoPopulateFromClipboard()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isURLFocused = true
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(alignment: .top, spacing: 14) {
            // Blue download icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x1C92FF), Color(hex: 0x006CE4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                Image(systemName: "arrow.down")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center) {
                    Text("Add New Download")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    // Engine status badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 6, height: 6)
                        Text("HyperFetch Engine")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.success)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.success.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Theme.success.opacity(0.25), lineWidth: 0.8)
                    )
                }

                Text("Enter a file URL to download with multi-chunk acceleration.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var sourceURLSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Source URL")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Button {
                    pasteFromClipboard()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10.5))
                        Text("⌘V Paste link")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Paste URL from clipboard")
            }

            // Input field
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)

                TextField("https://example.com/file.zip", text: $urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($isURLFocused)

                if !urlString.isEmpty {
                    Button {
                        urlString = ""
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.cardBorder, in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isURLFocused ? Theme.accent : Theme.inputBorder, lineWidth: isURLFocused ? 1.5 : 1)
            )

            if !urlString.isEmpty {
                if isValidURL {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.success)
                        Text("Valid HTTP/HTTPS download link")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.success)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.warning)
                        Text("Please enter a valid HTTP or HTTPS file address")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
        }
    }

    private var saveDestinationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Save Destination")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text(availableDiskSpaceString)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }

            // Destination folder card preview
            HStack(spacing: 12) {
                // macOS Folder Icon
                Image(systemName: "folder.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(hex: 0x2CA4FA))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(destinationFolderURL.lastPathComponent.isEmpty ? "Downloads" : destinationFolderURL.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        if isDefaultDownloadsFolder {
                            Text("Default")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Theme.tagBackground, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    Text(destinationFolderURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    chooseDestinationFolder()
                } label: {
                    Text("Change…")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
        }
    }

    private var filenameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text("Filename")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("(Optional)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                if let badge = detectedExtensionBadge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            TextField("Auto-detect from server or link", text: $customFilename)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.inputBorder, lineWidth: 1)
                )
        }
    }

    private var accelerationChunksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Acceleration Chunks")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text(chunkBenefitTitle(chunkCount))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
            }

            // Segmented pill control
            HStack(spacing: 4) {
                ForEach(chunkCountOptions, id: \.self) { count in
                    let isSelected = (chunkCount == count)
                    Button {
                        chunkCount = count
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Theme.cardActive : Color.white.opacity(0.001))
                                    .shadow(color: isSelected ? Color.black.opacity(0.15) : Color.clear, radius: 2, y: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isSelected ? Theme.cardBorderActive : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(3)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )

            Text(chunkBenefitDescription(chunkCount))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }

    private var optionsAndAdvancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Auto start checkbox
            Toggle(isOn: $autoStart) {
                Text("Start download immediately upon adding")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.checkbox)

            // Collapsible Advanced Disclosure
            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .overlay(Theme.separator)
                        .padding(.vertical, 2)

                    HStack {
                        Text("Custom Referrer / User-Agent:")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(customUserAgent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    HStack {
                        Text("Thread Priority:")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("Standard QoS (UserInteractive)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SHA-256 Verification Checksum:")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)

                        TextField("Optional expected SHA-256 hash", text: $sha256Checksum)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Theme.inputBorder, lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                    Text("Advanced Connection Options (Headers, Proxy, SHA-256)")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var footerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Text("Cancel")
                    Text("Esc")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                submitDownload()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .bold))
                    Text("Download Now")
                    Text("⏎")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(Theme.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(!isValidURL)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Theme.statusBarBackground)
        .overlay(alignment: .top) {
            Divider().overlay(Theme.separator)
        }
    }

    // MARK: - Helpers

    private var isValidURL: Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private var isDefaultDownloadsFolder: Bool {
        let defaultURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        return destinationFolderURL.standardizedFileURL.path == defaultURL.standardizedFileURL.path
    }

    private var availableDiskSpaceString: String {
        do {
            let values = try destinationFolderURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map({ Int64($0) }) {
                return "\(AppState.formatBytes(capacity)) available"
            }
        } catch {}
        return ""
    }

    private var detectedExtensionBadge: String? {
        let trimmedCustom = customFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            let ext = (trimmedCustom as NSString).pathExtension
            if !ext.isEmpty { return ".\(ext.lowercased()) detected" }
        }
        if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let ext = url.pathExtension
            if !ext.isEmpty { return ".\(ext.lowercased()) detected" }
        }
        return nil
    }

    private func autoPopulateFromClipboard() {
        if urlString.isEmpty, let clipURL = appState.getValidURLFromClipboard() {
            urlString = clipURL.absoluteString
        }
    }

    private func pasteFromClipboard() {
        if let clipURL = appState.getValidURLFromClipboard() {
            urlString = clipURL.absoluteString
        } else if let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !string.isEmpty {
            urlString = string
        }
    }

    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"
        panel.directoryURL = destinationFolderURL

        if panel.runModal() == .OK, let selectedURL = panel.url {
            destinationFolderURL = selectedURL
        }
    }

    private func chunkBenefitTitle(_ count: Int) -> String {
        switch count {
        case 1: return "Single Stream"
        case 2: return "2x Speedup"
        case 4: return "4x Speedup (Recommended)"
        case 8: return "8x Turbo Stream"
        case 16: return "16x Maximum Acceleration"
        default: return "\(count) Chunks"
        }
    }

    private func chunkBenefitDescription(_ count: Int) -> String {
        switch count {
        case 1:
            return "Single HTTP connection; suitable for simple servers or low-bandwidth links."
        case 2:
            return "Splits the file into 2 concurrent streams to improve throughput."
        case 4:
            return "Splits the file into 4 parallel chunks for optimal balance between speed and server load."
        case 8:
            return "Downloads 8 chunks concurrently to maximize throughput on high-speed fiber networks."
        case 16:
            return "Aggressively saturates gigabit connections with 16 parallel downloading threads."
        default:
            return "Splits into parallel chunks to maximize download bandwidth."
        }
    }

    private func submitDownload() {
        guard isValidURL, let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        let trimmedName = customFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalFilename = trimmedName.isEmpty ? nil : trimmedName

        let destinationFile: URL?
        if let finalFilename {
            destinationFile = destinationFolderURL.appendingPathComponent(finalFilename)
        } else {
            destinationFile = destinationFolderURL.appendingPathComponent(url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
        }

        appState.defaultChunkCount = chunkCount
        appState.defaultDownloadDirectoryURL = destinationFolderURL

        appState.addTask(
            url: url,
            destinationURL: destinationFile,
            filename: finalFilename,
            chunkCount: chunkCount,
            autoStart: autoStart
        )

        dismiss()
    }
}
