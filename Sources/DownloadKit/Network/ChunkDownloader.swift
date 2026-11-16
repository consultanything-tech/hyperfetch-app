import Foundation

/// Errors that can occur during individual chunk downloads.
public enum ChunkDownloadError: Error, LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
    case serverDoesNotSupportRange(statusCode: Int)
    case unexpectedEOF(expected: Int64, received: Int64)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid or non-HTTP response from server."
        case .httpError(let code):
            return "Server responded with HTTP error: \(code)"
        case .serverDoesNotSupportRange(let code):
            return "Server responded with HTTP \(code) instead of 206 Partial Content for range request."
        case .unexpectedEOF(let expected, let received):
            return "Stream terminated prematurely: expected \(expected) bytes, received \(received) bytes."
        case .cancelled:
            return "Chunk download was cancelled."
        }
    }
}

/// Protocol defining operations to download a single byte-range chunk.
public protocol ChunkDownloading: Sendable {
    func download(
        chunk: inout Chunk,
        from url: URL,
        to writer: FileWriting,
        headers: [String: String],
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws
}

extension ChunkDownloading {
    public func download(
        chunk: inout Chunk,
        from url: URL,
        to writer: FileWriting,
        headers: [String: String] = [:],
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await download(chunk: &chunk, from: url, to: writer, headers: headers, onProgress: onProgress)
    }

    public func download(
        chunk: inout Chunk,
        from url: URL,
        to writer: FileWriting,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await download(chunk: &chunk, from: url, to: writer, headers: [:], onProgress: onProgress)
    }
}

/// High-performance shared URLSession configured for high-throughput multi-chunk concurrent downloads.
public enum DownloadURLSession {
    public static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 32
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.networkServiceType = .responsiveData
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 86400.0
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
}

/// Downloads a single chunk using URLSession and writes directly to FileWriting at exact offsets.
public final class ChunkDownloader: ChunkDownloading, Sendable {
    private let session: URLSession
    public let rateLimiter: (any RateLimiting)?

    public init(session: URLSession = DownloadURLSession.shared, rateLimiter: (any RateLimiting)? = nil) {
        self.session = session
        self.rateLimiter = rateLimiter
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .timedOut, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if case ChunkDownloadError.unexpectedEOF = error {
            return true
        }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("network connection was lost") ||
               desc.contains("timed out") ||
               desc.contains("connection reset")
    }

    public func download(
        chunk: inout Chunk,
        from url: URL,
        to writer: FileWriting,
        headers: [String: String] = [:],
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        // If the chunk is already fully downloaded, mark completed and return
        if chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength {
            chunk.status = .completed
            return
        }

        var baseRequest = URLRequest(url: url)
        baseRequest.httpMethod = "GET"

        var resolvedHeaders = headers
        let hasUserAgent = resolvedHeaders.keys.contains { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }
        if !hasUserAgent {
            resolvedHeaders["User-Agent"] = HTTPRangeProbe.defaultUserAgent
        }
        let hasAcceptLanguage = resolvedHeaders.keys.contains { $0.caseInsensitiveCompare("Accept-Language") == .orderedSame }
        if !hasAcceptLanguage {
            baseRequest.setValue("", forHTTPHeaderField: "Accept-Language")
        }
        for (key, value) in resolvedHeaders {
            baseRequest.setValue(value, forHTTPHeaderField: key)
        }

        baseRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let chunkStartOffset = chunk.startOffset
        var attempt = 0
        let maxAttempts = 3

        while attempt < maxAttempts {
            attempt += 1

            if chunk.expectedLength > 0 && chunk.bytesDownloaded >= chunk.expectedLength {
                chunk.status = .completed
                return
            }

            var request = baseRequest
            let currentStart = chunkStartOffset + chunk.bytesDownloaded
            if chunk.endOffset >= 0 {
                request.setValue("bytes=\(currentStart)-\(chunk.endOffset)", forHTTPHeaderField: "Range")
            } else if currentStart > 0 {
                request.setValue("bytes=\(currentStart)-", forHTTPHeaderField: "Range")
            }

            chunk.status = .downloading

            let (dataStream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()

            let delegate = DataTaskStreamDelegate(continuation: continuation) { response in
                if response.statusCode == 206 {
                    // Expected Partial Content
                } else if response.statusCode == 200 {
                    // 200 OK is only valid if chunk begins at offset 0 (single-stream or entire file)
                    if currentStart > 0 {
                        throw ChunkDownloadError.serverDoesNotSupportRange(statusCode: 200)
                    }
                } else if response.statusCode >= 400 {
                    throw ChunkDownloadError.httpError(statusCode: response.statusCode)
                }
            }

            let task = session.dataTask(with: request)
            task.delegate = delegate
            task.resume()

            var downloadedSoFar = chunk.bytesDownloaded
            let expectedLength = chunk.expectedLength

            do {
                try await withTaskCancellationHandler {
                    for try await data in dataStream {
                        try Task.checkCancellation()
                        let count = Int64(data.count)
                        if let rateLimiter {
                            try await rateLimiter.requestTokens(count: count)
                        }
                        let writeOffset = chunkStartOffset + downloadedSoFar
                        try await writer.write(data: data, at: writeOffset)
                        downloadedSoFar += count
                        chunk.bytesDownloaded = downloadedSoFar
                        onProgress(count)
                    }

                    if Task.isCancelled {
                        throw CancellationError()
                    }

                    // Verify expected byte count if length is known
                    if expectedLength > 0 && downloadedSoFar < expectedLength {
                        let err = ChunkDownloadError.unexpectedEOF(
                            expected: expectedLength,
                            received: downloadedSoFar
                        )
                        throw err
                    }
                } onCancel: {
                    task.cancel()
                    continuation.finish(throwing: CancellationError())
                }

                chunk.bytesDownloaded = downloadedSoFar
                chunk.status = .completed
                return
            } catch is CancellationError {
                task.cancel()
                chunk.bytesDownloaded = downloadedSoFar
                chunk.status = .pending
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                task.cancel()
                chunk.bytesDownloaded = downloadedSoFar
                chunk.status = .pending
                throw CancellationError()
            } catch {
                task.cancel()
                chunk.bytesDownloaded = downloadedSoFar

                if Task.isCancelled {
                    chunk.status = .pending
                    throw CancellationError()
                }

                if isTransientNetworkError(error) && attempt < maxAttempts {
                    do {
                        let jitterNs = UInt64.random(in: 0..<200_000_000)
                        try await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000) + jitterNs)
                        continue
                    } catch {
                        chunk.status = .pending
                        throw CancellationError()
                    }
                }

                chunk.status = .failed(error.localizedDescription)
                throw error
            }
        }

        if chunk.status != .completed {
            chunk.status = .failed("Max retry attempts reached")
            throw ChunkDownloadError.invalidResponse
        }
    }
}

// MARK: - Streaming URLSession Delegate

final class DataTaskStreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let onResponseReceived: @Sendable (HTTPURLResponse) throws -> Void

    init(
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        onResponseReceived: @escaping @Sendable (HTTPURLResponse) throws -> Void
    ) {
        self.continuation = continuation
        self.onResponseReceived = onResponseReceived
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirectedRequest = request
        if let originalHeaders = task.originalRequest?.allHTTPHeaderFields {
            for (k, v) in originalHeaders {
                if redirectedRequest.value(forHTTPHeaderField: k) == nil {
                    redirectedRequest.setValue(v, forHTTPHeaderField: k)
                }
            }
        }
        completionHandler(redirectedRequest)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.finish(throwing: ChunkDownloadError.invalidResponse)
            completionHandler(.cancel)
            return
        }

        do {
            try onResponseReceived(httpResponse)
            completionHandler(.allow)
        } catch {
            continuation.finish(throwing: error)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                continuation.finish(throwing: CancellationError())
            } else {
                continuation.finish(throwing: error)
            }
        } else {
            continuation.finish()
        }
    }
}
