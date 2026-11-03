import Foundation

/// Represents content categories for downloaded files.
public enum DownloadCategory: String, Codable, CaseIterable, Sendable {
    case all = "All"
    case archives = "Archives"
    case documents = "Documents"
    case video = "Video"
    case music = "Music"
    case applications = "Applications"
    case other = "Other"

    /// The subfolder name under the downloads base directory for this category.
    public var folderName: String {
        switch self {
        case .applications: return "Applications"
        case .archives: return "Archives"
        case .documents: return "Documents"
        case .video: return "Video"
        case .music: return "Music"
        case .other, .all: return "Other"
        }
    }

    /// Automatically classifies a file into a `DownloadCategory` based on filename and extension.
    public static func category(for filename: String) -> DownloadCategory {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .other }
        let lower = trimmed.lowercased()

        // Check compound archive extensions first (e.g., tar.gz)
        let compoundArchives = [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.z", ".tar.lz"]
        for ext in compoundArchives {
            if lower.hasSuffix(ext) {
                return .archives
            }
        }

        // Extract extension after last dot
        guard let dotIndex = lower.lastIndex(of: ".") else {
            return .other
        }
        let ext = String(lower[lower.index(after: dotIndex)...])
        guard !ext.isEmpty else { return .other }

        switch ext {
        case "dmg", "pkg", "app", "exe", "msi", "apk", "ipa", "deb", "rpm":
            return .applications

        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "tgz", "tbz2", "z", "cab", "arj", "lz", "lzma":
            return .archives

        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "epub", "pages", "numbers", "keynote", "md", "odt", "ods", "odp":
            return .documents

        case "mp4", "mkv", "mov", "avi", "wmv", "flv", "webm", "m4v", "mpeg", "mpg", "3gp", "ts", "vob":
            return .video

        case "mp3", "wav", "flac", "aac", "ogg", "m4a", "aiff", "wma", "alac", "opus":
            return .music

        default:
            return .other
        }
    }
}
