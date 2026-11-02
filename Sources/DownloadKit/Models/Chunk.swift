import Foundation

/// Status of an individual chunk within a segmented download.
public enum ChunkStatus: Codable, Equatable, Sendable {
    case pending
    case downloading
    case completed
    case failed(String)
}

/// Represents a distinct byte-range chunk within a segmented download task.
public struct Chunk: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let index: Int
    public let startOffset: Int64
    public let endOffset: Int64
    public var bytesDownloaded: Int64
    public var status: ChunkStatus

    /// The closed byte range represented by this chunk.
    public var range: ClosedRange<Int64> {
        startOffset...endOffset
    }

    /// The expected total byte length of this chunk.
    public var expectedLength: Int64 {
        max(0, endOffset - startOffset + 1)
    }

    /// Progress ratio of this chunk between 0.0 and 1.0.
    public var progress: Double {
        guard expectedLength > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(bytesDownloaded) / Double(expectedLength)))
    }

    public init(
        id: UUID = UUID(),
        index: Int,
        startOffset: Int64,
        endOffset: Int64,
        bytesDownloaded: Int64 = 0,
        status: ChunkStatus = .pending
    ) {
        self.id = id
        self.index = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.bytesDownloaded = bytesDownloaded
        self.status = status
    }

    public init(
        id: UUID = UUID(),
        index: Int,
        range: ClosedRange<Int64>,
        bytesDownloaded: Int64 = 0,
        status: ChunkStatus = .pending
    ) {
        self.id = id
        self.index = index
        self.startOffset = range.lowerBound
        self.endOffset = range.upperBound
        self.bytesDownloaded = bytesDownloaded
        self.status = status
    }
}
