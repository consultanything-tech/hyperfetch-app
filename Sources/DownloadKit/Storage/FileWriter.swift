//
//  FileWriter.swift
//  DownloadKit
//

import Foundation
import Darwin

/// Errors that can occur during file writing and disk allocation operations.
public enum FileWriteError: Error, LocalizedError, Equatable, Sendable {
    case fileCreationFailed(String)
    case seekFailed(Int64)
    case writeFailed(errno: Int32, message: String)
    case allocationFailed(errno: Int32, message: String)
    case fileClosed

    public var errorDescription: String? {
        switch self {
        case .fileCreationFailed(let reason):
            return "Failed to create or open file: \(reason)"
        case .seekFailed(let offset):
            return "Failed to seek to offset: \(offset)"
        case .writeFailed(let errno, let message):
            return "File write failed (errno \(errno)): \(message)"
        case .allocationFailed(let errno, let message):
            return "File pre-allocation failed (errno \(errno)): \(message)"
        case .fileClosed:
            return "File writer is closed."
        }
    }
}

/// Protocol defining disk writing operations for chunked and streaming downloads.
public protocol FileWriting: Sendable {
    func allocate(totalBytes: Int64) async throws
    func write(data: Data, at offset: Int64) async throws
    func append(data: Data) async throws
    func sync() async throws
    func close() async
    func currentSize() async throws -> Int64
}

/// High-performance disk I/O engine supporting sparse pre-allocation and concurrent offset writing.
public actor FileWriter: FileWriting {
    public let destinationURL: URL
    private var fd: Int32 = -1
    private var isClosed: Bool = false
    private var initError: FileWriteError?

    public init(destinationURL: URL) {
        self.destinationURL = destinationURL
        let path = destinationURL.path
        guard !path.isEmpty else {
            self.initError = .fileCreationFailed("Destination URL path is empty: \(destinationURL)")
            self.fd = -1
            return
        }

        do {
            let parentDir = destinationURL.deletingLastPathComponent()
            if !parentDir.path.isEmpty && parentDir.path != path {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            let descriptor = Darwin.open(path, O_RDWR | O_CREAT, 0o644)
            if descriptor < 0 {
                let err = errno
                let msg = String(cString: strerror(err))
                self.initError = .fileCreationFailed("Failed to open file at \(path) (errno \(err)): \(msg)")
                self.fd = -1
            } else {
                self.fd = descriptor
                self.initError = nil
            }
        } catch {
            self.initError = .fileCreationFailed(error.localizedDescription)
            self.fd = -1
        }
    }

    deinit {
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    // MARK: - FileWriting Operations

    /// Pre-allocates a sparse target file of `totalBytes` using ftruncate.
    /// If totalBytes <= 0, the file is truncated to 0 bytes.
    public func allocate(totalBytes: Int64) throws {
        let descriptor = try validFileDescriptor()
        let targetBytes: off_t = max(0, off_t(totalBytes))
        if Darwin.ftruncate(descriptor, targetBytes) != 0 {
            let err = errno
            let msg = String(cString: strerror(err))
            throw FileWriteError.allocationFailed(errno: err, message: msg)
        }
    }

    /// Writes data directly at the given file offset using POSIX pwrite in a loop.
    public func write(data: Data, at offset: Int64) throws {
        guard !data.isEmpty else { return }
        guard offset >= 0 else {
            throw FileWriteError.seekFailed(offset)
        }

        let descriptor = try validFileDescriptor()
        let totalBytes = data.count
        var bytesWrittenTotal = 0

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            while bytesWrittenTotal < totalBytes {
                let currentOffset = off_t(offset + Int64(bytesWrittenTotal))
                let remainingBytes = totalBytes - bytesWrittenTotal
                let ptr = baseAddress.advanced(by: bytesWrittenTotal)
                let written = Darwin.pwrite(descriptor, ptr, remainingBytes, currentOffset)
                if written < 0 {
                    let err = errno
                    if err == EINTR {
                        continue
                    }
                    let msg = String(cString: strerror(err))
                    throw FileWriteError.writeFailed(errno: err, message: msg)
                } else if written == 0 {
                    let err = errno != 0 ? errno : EIO
                    let msg = String(cString: strerror(err))
                    throw FileWriteError.writeFailed(errno: err, message: "Zero bytes written (errno \(err)): \(msg)")
                }
                bytesWrittenTotal += written
            }
        }
    }

    /// Appends data to the current end of the file.
    public func append(data: Data) throws {
        guard !data.isEmpty else { return }
        let endOffset = try currentSize()
        try write(data: data, at: endOffset)
    }

    /// Flushes cached file data to disk via fsync.
    public func sync() throws {
        let descriptor = try validFileDescriptor()
        if Darwin.fsync(descriptor) != 0 {
            let err = errno
            let msg = String(cString: strerror(err))
            throw FileWriteError.writeFailed(errno: err, message: msg)
        }
    }

    /// Closes the underlying file descriptor safely.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    /// Returns the current size of the file in bytes.
    public func currentSize() throws -> Int64 {
        let descriptor = try validFileDescriptor()
        var statBuffer = stat()
        if Darwin.fstat(descriptor, &statBuffer) != 0 {
            throw FileWriteError.seekFailed(-1)
        }
        return Int64(statBuffer.st_size)
    }

    // MARK: - Private Helpers

    private func validFileDescriptor() throws -> Int32 {
        if isClosed {
            throw FileWriteError.fileClosed
        }
        if let initError {
            throw initError
        }
        guard fd >= 0 else {
            throw FileWriteError.fileClosed
        }
        return fd
    }
}
