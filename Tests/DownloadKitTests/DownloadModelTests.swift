import Testing
import Foundation
@testable import DownloadKit

@Suite("DownloadKit Core Domain Model Tests")
struct DownloadModelTests {

    // MARK: - DownloadCategory Tests

    @Test("Category deduction based on file extensions")
    func testCategoryDeduction() {
        // Applications
        #expect(DownloadCategory.category(for: "installer.dmg") == .applications)
        #expect(DownloadCategory.category(for: "Package.pkg") == .applications)
        #expect(DownloadCategory.category(for: "app.zip.dmg") == .applications)

        // Archives
        #expect(DownloadCategory.category(for: "archive.zip") == .archives)
        #expect(DownloadCategory.category(for: "archive.ZIP") == .archives)
        #expect(DownloadCategory.category(for: "backup.tar.gz") == .archives)
        #expect(DownloadCategory.category(for: "ubuntu-24.04.iso") == .archives)
        #expect(DownloadCategory.category(for: "data.7z") == .archives)
        #expect(DownloadCategory.category(for: "compressed.rar") == .archives)

        // Documents
        #expect(DownloadCategory.category(for: "document.pdf") == .documents)
        #expect(DownloadCategory.category(for: "notes.docx") == .documents)
        #expect(DownloadCategory.category(for: "data.csv") == .documents)
        #expect(DownloadCategory.category(for: "readme.txt") == .documents)

        // Video
        #expect(DownloadCategory.category(for: "movie.mp4") == .video)
        #expect(DownloadCategory.category(for: "clip.mkv") == .video)
        #expect(DownloadCategory.category(for: "stream.mov") == .video)

        // Music
        #expect(DownloadCategory.category(for: "song.mp3") == .music)
        #expect(DownloadCategory.category(for: "track.flac") == .music)
        #expect(DownloadCategory.category(for: "audio.wav") == .music)

        // Unknown / Other
        #expect(DownloadCategory.category(for: "unknown.xyz123") == .other)
        #expect(DownloadCategory.category(for: "noextension") == .other)
        #expect(DownloadCategory.category(for: "") == .other)
    }

    @Test("DownloadCategory folder names mapping")
    func testCategoryFolderNames() {
        #expect(DownloadCategory.applications.folderName == "Applications")
        #expect(DownloadCategory.archives.folderName == "Archives")
        #expect(DownloadCategory.documents.folderName == "Documents")
        #expect(DownloadCategory.video.folderName == "Video")
        #expect(DownloadCategory.music.folderName == "Music")
        #expect(DownloadCategory.other.folderName == "Other")
        #expect(DownloadCategory.all.folderName == "Other")
    }

    @Test("DownloadTaskModel assigns default destination to ~/Downloads/HyperFetch/<Category>/<Filename>")
    func testDefaultDestinationCategorization() {
        let baseDir = DownloadTaskModel.defaultBaseDirectory.standardizedFileURL

        let appTask = DownloadTaskModel(
            url: URL(string: "https://example.com/installer.dmg")!
        )
        #expect(appTask.category == .applications)
        #expect(appTask.destinationURL == baseDir.appendingPathComponent("Applications/installer.dmg").standardizedFileURL)

        let archiveTask = DownloadTaskModel(
            url: URL(string: "https://example.com/data.tar.gz")!
        )
        #expect(archiveTask.category == .archives)
        #expect(archiveTask.destinationURL == baseDir.appendingPathComponent("Archives/data.tar.gz").standardizedFileURL)

        let docTask = DownloadTaskModel(
            url: URL(string: "https://example.com/paper.pdf")!
        )
        #expect(docTask.category == .documents)
        #expect(docTask.destinationURL == baseDir.appendingPathComponent("Documents/paper.pdf").standardizedFileURL)

        let videoTask = DownloadTaskModel(
            url: URL(string: "https://example.com/clip.mp4")!
        )
        #expect(videoTask.category == .video)
        #expect(videoTask.destinationURL == baseDir.appendingPathComponent("Video/clip.mp4").standardizedFileURL)

        let musicTask = DownloadTaskModel(
            url: URL(string: "https://example.com/song.mp3")!
        )
        #expect(musicTask.category == .music)
        #expect(musicTask.destinationURL == baseDir.appendingPathComponent("Music/song.mp3").standardizedFileURL)

        let otherTask = DownloadTaskModel(
            url: URL(string: "https://example.com/blob.dat")!
        )
        #expect(otherTask.category == .other)
        #expect(otherTask.destinationURL == baseDir.appendingPathComponent("Other/blob.dat").standardizedFileURL)
    }

    // MARK: - Chunk Tests

    @Test("Chunk expected length and progress calculation")
    func testChunkProgressAndLength() {
        let chunkId = UUID()
        var chunk = Chunk(
            id: chunkId,
            index: 0,
            startOffset: 0,
            endOffset: 999,
            bytesDownloaded: 0,
            status: .pending
        )

        #expect(chunk.expectedLength == 1000)
        #expect(chunk.progress == 0.0)
        #expect(chunk.range == 0...999)

        chunk.bytesDownloaded = 250
        chunk.status = .downloading
        #expect(chunk.progress == 0.25)

        chunk.bytesDownloaded = 500
        #expect(chunk.progress == 0.5)

        chunk.bytesDownloaded = 1000
        chunk.status = .completed
        #expect(chunk.progress == 1.0)

        // Test clamping
        chunk.bytesDownloaded = 1200
        #expect(chunk.progress == 1.0)
    }

    @Test("Chunk equality comparison")
    func testChunkEquality() {
        let chunkId = UUID()
        let chunk1 = Chunk(
            id: chunkId,
            index: 1,
            range: 1000...1999,
            bytesDownloaded: 500,
            status: .downloading
        )
        let chunk2 = Chunk(
            id: chunkId,
            index: 1,
            range: 1000...1999,
            bytesDownloaded: 500,
            status: .downloading
        )
        let chunk3 = Chunk(
            id: chunkId,
            index: 1,
            range: 1000...1999,
            bytesDownloaded: 600,
            status: .downloading
        )

        #expect(chunk1 == chunk2)
        #expect(chunk1 != chunk3)
    }

    // MARK: - DownloadTaskModel Tests

    @Test("DownloadTaskModel progress calculation")
    func testDownloadTaskProgress() {
        let url = URL(string: "https://example.com/file.zip")!
        var task = DownloadTaskModel(
            url: url,
            filename: "file.zip",
            destinationURL: URL(fileURLWithPath: "/tmp/file.zip"),
            totalBytes: 2000,
            downloadedBytes: 500,
            status: .downloading
        )

        #expect(task.progress == 0.25)

        task.downloadedBytes = 2000
        task.status = .completed
        #expect(task.progress == 1.0)

        // Unknown total bytes
        var taskUnknown = DownloadTaskModel(
            url: url,
            filename: "file.zip",
            destinationURL: URL(fileURLWithPath: "/tmp/file.zip"),
            totalBytes: -1,
            downloadedBytes: 500,
            status: .downloading
        )
        #expect(taskUnknown.progress == 0.0)

        taskUnknown.status = .completed
        #expect(taskUnknown.progress == 1.0)
    }

    @Test("DownloadTaskModel and Chunk Codable roundtrip")
    func testCodableRoundtrip() throws {
        let taskId = UUID()
        let chunk1Id = UUID()
        let chunk2Id = UUID()
        let now = Date(timeIntervalSince1970: 1700000000)
        let completedDate = Date(timeIntervalSince1970: 1700003600)

        let chunks = [
            Chunk(
                id: chunk1Id,
                index: 0,
                range: 0...999,
                bytesDownloaded: 1000,
                status: .completed
            ),
            Chunk(
                id: chunk2Id,
                index: 1,
                range: 1000...1999,
                bytesDownloaded: 200,
                status: .failed("Connection reset")
            )
        ]

        let originalTask = DownloadTaskModel(
            id: taskId,
            url: URL(string: "https://releases.ubuntu.com/noble/ubuntu-24.04-desktop-amd64.iso")!,
            filename: "ubuntu-24.04-desktop-amd64.iso",
            destinationURL: URL(fileURLWithPath: "/Users/test/Downloads/ubuntu-24.04-desktop-amd64.iso"),
            totalBytes: 2000,
            downloadedBytes: 1200,
            status: .failed(reason: "Connection reset"),
            chunks: chunks,
            supportsRange: true,
            createdAt: now,
            completedAt: completedDate,
            category: .archives
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(originalTask)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedTask = try decoder.decode(DownloadTaskModel.self, from: encodedData)

        #expect(decodedTask == originalTask)
        #expect(decodedTask.id == originalTask.id)
        #expect(decodedTask.url == originalTask.url)
        #expect(decodedTask.filename == originalTask.filename)
        #expect(decodedTask.destinationURL == originalTask.destinationURL)
        #expect(decodedTask.totalBytes == originalTask.totalBytes)
        #expect(decodedTask.downloadedBytes == originalTask.downloadedBytes)
        #expect(decodedTask.status == originalTask.status)
        #expect(decodedTask.chunks == originalTask.chunks)
        #expect(decodedTask.supportsRange == originalTask.supportsRange)
        #expect(decodedTask.category == originalTask.category)
        #expect(decodedTask.completedAt == originalTask.completedAt)
        #expect(decodedTask.headers == originalTask.headers)
    }

    @Test("DownloadTaskModel backwards compatibility: missing headers decodes to empty dictionary")
    func testBackwardsCompatibilityMissingHeaders() throws {
        let jsonWithoutHeaders = """
        {
            "id": "2808F840-E873-4ED7-B4E3-DBB7D09D70A0",
            "url": "https://example.com/movie.mp4",
            "filename": "movie.mp4",
            "destinationURL": "file:///Users/test/Downloads/movie.mp4",
            "totalBytes": -1,
            "downloadedBytes": 0,
            "status": { "idle": {} },
            "chunks": [],
            "supportsRange": false,
            "createdAt": "2026-11-02T04:34:33Z",
            "category": "Video",
            "bytesPerSecond": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode(DownloadTaskModel.self, from: jsonWithoutHeaders)

        #expect(task.filename == "movie.mp4")
        #expect(task.headers == [:])
        #expect(task.preferredChunkCount == nil)
        #expect(task.supportsRange == false)
    }

    @Test("DownloadTaskModel with preferredChunkCount roundtrips via Codable")
    func testPreferredChunkCountCodable() throws {
        let task = DownloadTaskModel(
            url: URL(string: "https://example.com/file.zip")!,
            filename: "file.zip",
            preferredChunkCount: 8
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(task)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DownloadTaskModel.self, from: data)

        #expect(decoded.preferredChunkCount == 8)
    }

    @Test("DownloadTaskModel with custom headers preserves headers through Codable")
    func testHeadersPreservedInCodable() throws {
        let taskWithHeaders = DownloadTaskModel(
            url: URL(string: "https://docs.google.com/export")!,
            filename: "Doc.pdf",
            headers: [
                "Cookie": "test_cookie=123",
                "Referer": "https://docs.google.com"
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(taskWithHeaders)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DownloadTaskModel.self, from: data)

        #expect(decoded.headers["Cookie"] == "test_cookie=123")
        #expect(decoded.headers["Referer"] == "https://docs.google.com")
    }

    @Test("DownloadStatus all cases Codable roundtrip")
    func testDownloadStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let statuses: [DownloadStatus] = [
            .idle,
            .probing,
            .downloading,
            .paused,
            .completed,
            .failed(reason: "Disk full")
        ]

        for status in statuses {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(DownloadStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    @Test("DownloadTaskModel with etag and lastModified roundtrips via Codable")
    func testETagAndLastModifiedCodable() throws {
        let task = DownloadTaskModel(
            url: URL(string: "https://example.com/file.bin")!,
            filename: "file.bin",
            etag: "\"33a64df551425fcc55e4d42a148795d9f25f89d4\"",
            lastModified: "Wed, 21 Oct 2025 07:28:00 GMT"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(task)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DownloadTaskModel.self, from: data)

        #expect(decoded.etag == "\"33a64df551425fcc55e4d42a148795d9f25f89d4\"")
        #expect(decoded.lastModified == "Wed, 21 Oct 2025 07:28:00 GMT")
    }

    @Test("DownloadTaskModel decodes cleanly when etag and lastModified are omitted")
    func testMissingETagAndLastModifiedBackwardsCompatibility() throws {
        let jsonWithoutEtag = """
        {
            "id": "A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D",
            "url": "https://example.com/test.zip",
            "filename": "test.zip",
            "destinationURL": "file:///tmp/test.zip",
            "totalBytes": 1024,
            "downloadedBytes": 512,
            "status": { "idle": {} },
            "chunks": [],
            "supportsRange": true,
            "createdAt": "2026-01-01T00:00:00Z",
            "category": "Archives",
            "bytesPerSecond": 0.0
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let task = try decoder.decode(DownloadTaskModel.self, from: Data(jsonWithoutEtag.utf8))

        #expect(task.etag == nil)
        #expect(task.lastModified == nil)
    }
}
