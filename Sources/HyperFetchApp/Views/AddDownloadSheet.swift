//
//  AddDownloadSheet.swift
//  HyperFetchApp
//

import AppKit
import SwiftUI
import DownloadKit

/// Modal sheet for entering a download URL, target directory, and connection options.
public struct AddDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @FocusState private var isURLFocused: Bool
    @ViewState private var urlString: String = ""
    @ViewState private var customFilename: String = ""
    @ViewState private var destinationFolderURL: URL
    @ViewState private var chunkCount: Int = 4
    @ViewState private var autoStart: Bool = true

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
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add New Download")
                        .font(.headline)
                    Text("Enter a file URL to download with multi-chunk acceleration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Form Fields
            VStack(alignment: .leading, spacing: 16) {
                // URL input section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source URL")
                        .font(.system(size: 13, weight: .semibold))

                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)

                            TextField("https://example.com/file.zip", text: $urlString)
                                .textFieldStyle(.plain)
                                .focused($isURLFocused)

                            if !urlString.isEmpty {
                                Button {
                                    urlString = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Clear URL")
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                        if let clipURL = appState.getValidURLFromClipboard() {
                            Button {
                                urlString = clipURL.absoluteString
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)
                            .help("Paste URL from clipboard")
                        }
                    }

                    // Dynamic URL validation indicator
                    if !urlString.isEmpty {
                        if isValidURL {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Valid HTTP/HTTPS URL")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Please enter a valid HTTP or HTTPS URL")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                // File Destination Preview Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save Destination")
                        .font(.system(size: 13, weight: .semibold))

                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(destinationFolderURL.lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))

                            Text(destinationFolderURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button("Change...") {
                            chooseDestinationFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                }

                // Custom Filename (Optional)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filename (Optional)")
                        .font(.system(size: 13, weight: .semibold))

                    TextField("Auto-detect from server or link", text: $customFilename)
                        .textFieldStyle(.roundedBorder)
                }

                // Number of concurrent chunk connections
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Acceleration Chunks")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(chunkBenefitTitle(chunkCount))
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    }

                    Picker("Chunks", selection: $chunkCount) {
                        ForEach(chunkCountOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(chunkBenefitDescription(chunkCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Auto Start Option
                Toggle("Start download immediately upon adding", isOn: $autoStart)
                    .font(.subheadline)
            }

            Spacer()

            Divider()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    submitDownload()
                } label: {
                    Label("Download Now", systemImage: "arrow.down.circle.fill")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidURL)
            }
        }
        .padding(22)
        .frame(width: 520, height: 490)
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

    private func autoPopulateFromClipboard() {
        if urlString.isEmpty, let clipURL = appState.getValidURLFromClipboard() {
            urlString = clipURL.absoluteString
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
