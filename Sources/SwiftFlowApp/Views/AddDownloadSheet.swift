//
//  AddDownloadSheet.swift
//  SwiftFlowApp
//

import AppKit
import SwiftUI
import DownloadKit

/// Modal sheet for entering a download URL, target directory, and connection options.
public struct AddDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @ViewState private var urlString: String = ""
    @ViewState private var customFilename: String = ""
    @ViewState private var destinationFolderURL: URL
    @ViewState private var chunkCount: Int = 4
    @ViewState private var autoStart: Bool = true

    private let chunkCountOptions = [1, 2, 4, 8, 16]

    public init() {
        let defaultDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        _destinationFolderURL = ViewState(wrappedValue: defaultDownloads)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("Add New Download")
                    .font(.headline)

                Spacer()
            }

            // Form Fields
            VStack(alignment: .leading, spacing: 14) {
                // URL input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download URL")
                        .font(.subheadline.bold())

                    HStack {
                        TextField("https://example.com/file.zip", text: $urlString)
                            .textFieldStyle(.roundedBorder)

                        if let clipURL = appState.getValidURLFromClipboard() {
                            Button("Paste") {
                                urlString = clipURL.absoluteString
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // Destination Directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Save To")
                        .font(.subheadline.bold())

                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)

                        Text(destinationFolderURL.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Browse...") {
                            chooseDestinationFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }

                // Custom Filename (Optional)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filename (Optional)")
                        .font(.subheadline.bold())

                    TextField("Auto-detect from server or link", text: $customFilename)
                        .textFieldStyle(.roundedBorder)
                }

                // Number of concurrent chunk connections
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parallel Connection Chunks")
                        .font(.subheadline.bold())

                    Picker("Chunks", selection: $chunkCount) {
                        ForEach(chunkCountOptions, id: \.self) { count in
                            Text("\(count) connections").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Splitting into multiple chunks maximizes throughput for fast networks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Auto Start Option
                Toggle("Start download immediately", isOn: $autoStart)
                    .font(.subheadline)
            }

            Spacer()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Download Now") {
                    submitDownload()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidURL)
            }
        }
        .padding(24)
        .frame(width: 500, height: 420)
        .onAppear {
            autoPopulateFromClipboard()
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

        appState.addTask(
            url: url,
            destinationURL: destinationFile,
            filename: finalFilename,
            autoStart: autoStart
        )

        dismiss()
    }
}
