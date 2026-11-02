//
//  ServicesProvider.swift
//  HyperFetchApp
//

import AppKit

@MainActor
public final class HyperFetchServiceProvider: NSObject {
    public static let shared = HyperFetchServiceProvider()
    public weak var appState: AppState?

    @objc public func downloadWithHyperFetch(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let text = pboard.string(forType: .string) ?? pboard.string(forType: .init("public.url")) ?? pboard.string(forType: .URL),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self, let appState = self.appState else { return }
            appState.handleIncomingDownload(url: url, filename: nil, autoStart: true)
        }
    }
}
