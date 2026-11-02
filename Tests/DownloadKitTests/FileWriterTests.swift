//
//  FileWriterTests.swift
//  DownloadKitTests
//

import Testing
import Foundation
@testable import DownloadKit

@Suite("FileWriter Disk I/O Tests")
struct FileWriterTests {

    private func createTempFileURL(filename: String = "testfile.dat") -> (directory: URL, file: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWriterTests_\(UUID().uuidString)")
        let fileURL = tempDir.appendingPathComponent(filename)
        return (tempDir, fileURL)
    }

    private func cleanup(directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 1. Sparse Pre-allocation

    @Test("Sparse pre-allocation to exact byte count (5 MB)")
    func testSparsePreAllocation() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)
        let fiveMB: Int64 = 5 * 1024 * 1024

        try await writer.allocate(totalBytes: fiveMB)
        let size = try await writer.currentSize()
        #expect(size == fiveMB)

        await writer.close()

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let diskSize = attrs[.size] as? Int64
        #expect(diskSize == fiveMB)
    }

    @Test("Allocation with zero or negative bytes truncates to 0")
    func testAllocateZeroOrNegative() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)

        // Pre-allocate 1 MB
        try await writer.allocate(totalBytes: 1024 * 1024)
        #expect(try await writer.currentSize() == 1024 * 1024)

        // Truncate to negative -> truncates to 0
        try await writer.allocate(totalBytes: -500)
        #expect(try await writer.currentSize() == 0)

        // Truncate to 0
        try await writer.allocate(totalBytes: 100)
        #expect(try await writer.currentSize() == 100)
        try await writer.allocate(totalBytes: 0)
        #expect(try await writer.currentSize() == 0)

        await writer.close()
    }

    // MARK: - 2. Non-Contiguous Direct Offset Writes

    @Test("Non-contiguous offset writes and zero-byte gap integrity")
    func testNonContiguousWrites() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)
        let totalSize: Int64 = 5_000_010
        try await writer.allocate(totalBytes: totalSize)

        let startData = Data("START_CHUNK".utf8)
        let middleData = Data("MIDDLE_CHUNK".utf8)
        let endData = Data("END_CHUNK".utf8)

        let startOffset: Int64 = 0
        let middleOffset: Int64 = 1_000
        let endOffset: Int64 = 5_000_000

        try await writer.write(data: startData, at: startOffset)
        try await writer.write(data: middleData, at: middleOffset)
        try await writer.write(data: endData, at: endOffset)
        try await writer.sync()
        await writer.close()

        let fileData = try Data(contentsOf: fileURL)
        #expect(fileData.count >= Int(endOffset) + endData.count)

        // Check start chunk
        let readStart = fileData.subdata(in: Int(startOffset)..<(Int(startOffset) + startData.count))
        #expect(readStart == startData)

        // Check untouched gap between start and middle (all zeros)
        let gap1 = fileData.subdata(in: (Int(startOffset) + startData.count)..<Int(middleOffset))
        #expect(gap1.allSatisfy { $0 == 0 })

        // Check middle chunk
        let readMiddle = fileData.subdata(in: Int(middleOffset)..<(Int(middleOffset) + middleData.count))
        #expect(readMiddle == middleData)

        // Check untouched gap between middle and end (all zeros)
        let gap2 = fileData.subdata(in: (Int(middleOffset) + middleData.count)..<Int(endOffset))
        #expect(gap2.allSatisfy { $0 == 0 })

        // Check end chunk
        let readEnd = fileData.subdata(in: Int(endOffset)..<(Int(endOffset) + endData.count))
        #expect(readEnd == endData)
    }

    // MARK: - 3. Concurrent Multi-Task Writes

    @Test("Concurrent writes from multiple async Tasks at disjoint offsets")
    func testConcurrentWrites() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)
        let chunkCount = 32
        let chunkSize = 4096
        let totalSize = Int64(chunkCount * chunkSize)

        try await writer.allocate(totalBytes: totalSize)

        // Launch concurrent tasks to write disjoint chunks simultaneously
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<chunkCount {
                group.addTask {
                    let offset = Int64(index * chunkSize)
                    // Unique deterministic fill pattern for each chunk
                    let byteVal = UInt8((index * 7 + 13) % 251)
                    let chunkPayload = Data(repeating: byteVal, count: chunkSize)
                    try await writer.write(data: chunkPayload, at: offset)
                }
            }
            try await group.waitForAll()
        }

        try await writer.sync()
        await writer.close()

        let fileData = try Data(contentsOf: fileURL)
        #expect(fileData.count == Int(totalSize))

        // Verify each chunk has exact expected payload
        for index in 0..<chunkCount {
            let offset = index * chunkSize
            let expectedByteVal = UInt8((index * 7 + 13) % 251)
            let chunkData = fileData.subdata(in: offset..<(offset + chunkSize))
            #expect(chunkData.allSatisfy { $0 == expectedByteVal })
        }
    }

    // MARK: - 4. Streaming Append Mode

    @Test("Append mode for indeterminate streams")
    func testAppendMode() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)

        let segment1 = Data("SwiftFlow".utf8)
        let segment2 = Data("-Download-".utf8)
        let segment3 = Data("Manager".utf8)

        try await writer.append(data: segment1)
        #expect(try await writer.currentSize() == Int64(segment1.count))

        try await writer.append(data: segment2)
        #expect(try await writer.currentSize() == Int64(segment1.count + segment2.count))

        try await writer.append(data: segment3)
        #expect(try await writer.currentSize() == Int64(segment1.count + segment2.count + segment3.count))

        await writer.close()

        let fullData = try Data(contentsOf: fileURL)
        let expectedString = "SwiftFlow-Download-Manager"
        #expect(String(data: fullData, encoding: .utf8) == expectedString)
    }

    // MARK: - 5. Directory Auto-Creation

    @Test("Parent directory auto-creation when destination is deeply nested")
    func testParentDirectoryAutoCreation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NestedTest_\(UUID().uuidString)")
        defer { cleanup(directory: tempDir) }

        let deeplyNestedURL = tempDir
            .appendingPathComponent("sub1")
            .appendingPathComponent("sub2")
            .appendingPathComponent("sub3")
            .appendingPathComponent("output.bin")

        let parentDir = deeplyNestedURL.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: parentDir.path))

        let writer = FileWriter(destinationURL: deeplyNestedURL)
        #expect(FileManager.default.fileExists(atPath: parentDir.path))

        let sampleData = Data([0xCA, 0xFE, 0xBA, 0xBE])
        try await writer.write(data: sampleData, at: 0)
        await writer.close()

        #expect(FileManager.default.fileExists(atPath: deeplyNestedURL.path))
        let writtenData = try Data(contentsOf: deeplyNestedURL)
        #expect(writtenData == sampleData)
    }

    // MARK: - 6. Post-Close Error Handling

    @Test("Error handling when operations are attempted after close()")
    func testOperationsAfterClose() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)
        await writer.close()

        // Subsequent closes are idempotent
        await writer.close()

        await #expect(throws: FileWriteError.fileClosed) {
            try await writer.write(data: Data([1, 2, 3]), at: 0)
        }

        await #expect(throws: FileWriteError.fileClosed) {
            try await writer.allocate(totalBytes: 1024)
        }

        await #expect(throws: FileWriteError.fileClosed) {
            try await writer.append(data: Data([4, 5, 6]))
        }

        await #expect(throws: FileWriteError.fileClosed) {
            try await writer.sync()
        }

        await #expect(throws: FileWriteError.fileClosed) {
            _ = try await writer.currentSize()
        }
    }

    // MARK: - 7. Edge Cases & Errors

    @Test("Negative offset throws seekFailed")
    func testNegativeOffsetThrows() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)

        await #expect(throws: FileWriteError.seekFailed(-1)) {
            try await writer.write(data: Data([1, 2, 3]), at: -1)
        }

        await writer.close()
    }

    @Test("Empty data write and append are no-ops")
    func testEmptyDataNoOps() async throws {
        let (tempDir, fileURL) = createTempFileURL()
        defer { cleanup(directory: tempDir) }

        let writer = FileWriter(destinationURL: fileURL)

        try await writer.write(data: Data(), at: 0)
        try await writer.append(data: Data())
        #expect(try await writer.currentSize() == 0)

        await writer.close()
    }

    @Test("FileWriteError descriptions and equality")
    func testErrorDescriptionsAndEquality() {
        let err1 = FileWriteError.fileCreationFailed("Permission denied")
        let err2 = FileWriteError.fileCreationFailed("Permission denied")
        let err3 = FileWriteError.fileCreationFailed("Disk error")
        #expect(err1 == err2)
        #expect(err1 != err3)
        #expect(err1.errorDescription?.contains("Permission denied") == true)

        let seekErr = FileWriteError.seekFailed(-10)
        #expect(seekErr.errorDescription?.contains("-10") == true)

        let writeErr = FileWriteError.writeFailed(errno: 28, message: "No space left on device")
        #expect(writeErr.errorDescription?.contains("28") == true)
        #expect(writeErr.errorDescription?.contains("No space left") == true)

        let allocErr = FileWriteError.allocationFailed(errno: 12, message: "Cannot allocate memory")
        #expect(allocErr.errorDescription?.contains("12") == true)

        let closedErr = FileWriteError.fileClosed
        #expect(closedErr.errorDescription == "File writer is closed.")
    }
}
