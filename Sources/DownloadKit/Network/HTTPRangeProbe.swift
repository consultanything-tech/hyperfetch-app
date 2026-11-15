import Foundation

/// Represents the inspected capabilities and metadata of a remote downloadable resource.
public struct ProbeResult: Equatable, Sendable {
    /// The total file size in bytes, or -1 if indeterminate (e.g. dynamic stream).
    public let totalBytes: Int64
    /// Indicates whether the server supports HTTP Range requests for segmented downloading.
    public let supportsRange: Bool
    /// The resolved filename derived from Content-Disposition, URL path, or default fallback.
    public let filename: String
    /// The ETag entity tag header returned by the server, if present.
    public let etag: String?
    /// The Last-Modified date header returned by the server, if present.
    public let lastModified: String?
    /// The final destination URL after any HTTP redirects.
    public let finalURL: URL

    public init(
        totalBytes: Int64,
        supportsRange: Bool,
        filename: String,
        etag: String? = nil,
        lastModified: String? = nil,
        finalURL: URL
    ) {
        self.totalBytes = totalBytes
        self.supportsRange = supportsRange
        self.filename = filename
        self.etag = etag
        self.lastModified = lastModified
        self.finalURL = finalURL
    }
}

/// Errors that can occur during remote HTTP resource probing.
public enum ProbeError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL(URL)
    case invalidResponse
    case httpError(statusCode: Int, url: URL)
    case networkError(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid or unsupported URL scheme: \(url.absoluteString)"
        case .invalidResponse:
            return "Received an invalid or non-HTTP response from server."
        case .httpError(let statusCode, let url):
            return "HTTP error \(statusCode) probing \(url.absoluteString)"
        case .networkError(let message):
            return "Network failure while probing: \(message)"
        case .cancelled:
            return "Probe operation was cancelled."
        }
    }
}

/// Defines an interface for probing remote HTTP endpoints prior to download.
public protocol HTTPProbing: Sendable {
    func probe(url: URL, headers: [String: String]) async throws -> ProbeResult
}

extension HTTPProbing {
    public func probe(url: URL) async throws -> ProbeResult {
        try await probe(url: url, headers: [:])
    }
}

/// Task delegate to preserve Cookie, User-Agent, and Referer headers across redirects (including cross-domain).
final class HTTPProbeRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
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
}

/// Robust HTTP prober that discovers content size, range support, filename, and cache validators.
public final class HTTPRangeProbe: HTTPProbing, Sendable {
    public static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private let session: URLSession
    private let timeoutInterval: TimeInterval
    private let redirectDelegate = HTTPProbeRedirectDelegate()

    public init(session: URLSession = .shared, timeoutInterval: TimeInterval = 60.0) {
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    public func probe(url: URL, headers: [String: String] = [:]) async throws -> ProbeResult {
        // Validate URL scheme
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ProbeError.invalidURL(url)
        }

        do {
            return try await performHeadProbe(url: url, headers: headers)
        } catch let error as ProbeError {
            throw error
        } catch is CancellationError {
            throw ProbeError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw ProbeError.cancelled
        } catch {
            throw ProbeError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Private Probe Execution

    private func applyHeaders(to request: inout URLRequest, customHeaders: [String: String]) {
        var resolved = customHeaders
        let hasUserAgent = resolved.keys.contains { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }
        if !hasUserAgent {
            resolved["User-Agent"] = Self.defaultUserAgent
        }
        let hasAcceptLanguage = resolved.keys.contains { $0.caseInsensitiveCompare("Accept-Language") == .orderedSame }
        if !hasAcceptLanguage {
            request.setValue("", forHTTPHeaderField: "Accept-Language")
        }
        for (key, value) in resolved {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func performHeadProbe(url: URL, headers: [String: String]) async throws -> ProbeResult {
        var headRequest = URLRequest(url: url, timeoutInterval: timeoutInterval)
        headRequest.httpMethod = "HEAD"
        applyHeaders(to: &headRequest, customHeaders: headers)
        headRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let (_, response) = try await session.data(for: headRequest, delegate: redirectDelegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.invalidResponse
        }

        let finalURL = httpResponse.url ?? url

        // Server does not support HEAD method or rejects HEAD (e.g. 401, 403, 405, 500, 501, or redirect) -> fallback to GET Range
        if httpResponse.statusCode >= 300 {
            return try await performGetRangeProbe(url: finalURL, headers: headers, headResponse: httpResponse)
        }

        let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")
        let supportsRange = acceptRanges?.localizedCaseInsensitiveContains("bytes") == true

        let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length")
        let contentLength = contentLengthStr.flatMap { Int64($0) } ?? -1

        // If Accept-Ranges is absent / not bytes, or Content-Length is missing, fallback to GET Range
        if !supportsRange || contentLength < 0 {
            return try await performGetRangeProbe(url: finalURL, headers: headers, headResponse: httpResponse)
        }

        let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
        let filename = FilenameResolver.resolve(contentDisposition: contentDisposition, finalURL: finalURL)
        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
        let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        return ProbeResult(
            totalBytes: contentLength,
            supportsRange: true,
            filename: filename,
            etag: etag,
            lastModified: lastModified,
            finalURL: finalURL
        )
    }

    private func performGetRangeProbe(url: URL, headers: [String: String], headResponse: HTTPURLResponse?) async throws -> ProbeResult {
        var getRequest = URLRequest(url: url, timeoutInterval: timeoutInterval)
        getRequest.httpMethod = "GET"
        applyHeaders(to: &getRequest, customHeaders: headers)
        getRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        getRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let (_, response) = try await session.data(for: getRequest, delegate: redirectDelegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.invalidResponse
        }

        let finalURL = httpResponse.url ?? url

        if httpResponse.statusCode == 206 {
            // Partial Content returned: byte-range requests are supported!
            let totalBytes: Int64
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
               let parsedTotal = parseContentRangeTotalBytes(contentRange) {
                totalBytes = parsedTotal
            } else {
                totalBytes = -1
            }

            let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
                ?? headResponse?.value(forHTTPHeaderField: "Content-Disposition")
            let filename = FilenameResolver.resolve(contentDisposition: disposition, finalURL: finalURL)
            let etag = httpResponse.value(forHTTPHeaderField: "ETag") ?? headResponse?.value(forHTTPHeaderField: "ETag")
            let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") ?? headResponse?.value(forHTTPHeaderField: "Last-Modified")

            return ProbeResult(
                totalBytes: totalBytes,
                supportsRange: true,
                filename: filename,
                etag: etag,
                lastModified: lastModified,
                finalURL: finalURL
            )
        } else if httpResponse.statusCode == 200 {
            // Server ignored Range header, entire stream only
            let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length")
            let totalBytes = contentLengthStr.flatMap { Int64($0) } ?? -1

            let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
                ?? headResponse?.value(forHTTPHeaderField: "Content-Disposition")
            let filename = FilenameResolver.resolve(contentDisposition: disposition, finalURL: finalURL)
            let etag = httpResponse.value(forHTTPHeaderField: "ETag") ?? headResponse?.value(forHTTPHeaderField: "ETag")
            let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") ?? headResponse?.value(forHTTPHeaderField: "Last-Modified")

            return ProbeResult(
                totalBytes: totalBytes,
                supportsRange: false,
                filename: filename,
                etag: etag,
                lastModified: lastModified,
                finalURL: finalURL
            )
        } else if httpResponse.statusCode == 416 {
            // Range Not Satisfiable: could be empty (0 byte) file
            var totalBytes: Int64 = -1
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
               let parsedTotal = parseContentRangeTotalBytes(contentRange) {
                totalBytes = parsedTotal
            }
            if totalBytes == 0 {
                let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
                    ?? headResponse?.value(forHTTPHeaderField: "Content-Disposition")
                let filename = FilenameResolver.resolve(contentDisposition: disposition, finalURL: finalURL)
                return ProbeResult(
                    totalBytes: 0,
                    supportsRange: true,
                    filename: filename,
                    etag: httpResponse.value(forHTTPHeaderField: "ETag") ?? headResponse?.value(forHTTPHeaderField: "ETag"),
                    lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified") ?? headResponse?.value(forHTTPHeaderField: "Last-Modified"),
                    finalURL: finalURL
                )
            }
            return try await performPlainGetProbe(url: finalURL, headers: headers, headResponse: headResponse ?? httpResponse)
        } else if httpResponse.statusCode >= 400 {
            // Server returned 4xx or 5xx to Range GET -> try plain GET without Range
            return try await performPlainGetProbe(url: finalURL, headers: headers, headResponse: headResponse ?? httpResponse)
        } else {
            throw ProbeError.httpError(statusCode: httpResponse.statusCode, url: finalURL)
        }
    }

    private func performPlainGetProbe(url: URL, headers: [String: String], headResponse: HTTPURLResponse?) async throws -> ProbeResult {
        var plainRequest = URLRequest(url: url, timeoutInterval: timeoutInterval)
        plainRequest.httpMethod = "GET"
        applyHeaders(to: &plainRequest, customHeaders: headers)
        // Range header is deliberately omitted
        plainRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        // Use session.bytes rather than session.data to read response headers immediately
        // without buffering large/infinite response bodies into RAM.
        let (_, response) = try await session.bytes(for: plainRequest, delegate: redirectDelegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.invalidResponse
        }

        let finalURL = httpResponse.url ?? url

        if httpResponse.statusCode == 200 {
            let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length")
            let totalBytes = contentLengthStr.flatMap { Int64($0) } ?? -1

            let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition")
                ?? headResponse?.value(forHTTPHeaderField: "Content-Disposition")
            let filename = FilenameResolver.resolve(contentDisposition: disposition, finalURL: finalURL)
            let etag = httpResponse.value(forHTTPHeaderField: "ETag") ?? headResponse?.value(forHTTPHeaderField: "ETag")
            let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified") ?? headResponse?.value(forHTTPHeaderField: "Last-Modified")

            return ProbeResult(
                totalBytes: totalBytes,
                supportsRange: false,
                filename: filename,
                etag: etag,
                lastModified: lastModified,
                finalURL: finalURL
            )
        } else {
            throw ProbeError.httpError(statusCode: httpResponse.statusCode, url: finalURL)
        }
    }

    private func parseContentRangeTotalBytes(_ header: String) -> Int64? {
        // Formats: "bytes 0-0/52428800" or "bytes */52428800" or "bytes 0-0/*"
        guard let slashIndex = header.lastIndex(of: "/") else { return nil }
        let sizePart = header[header.index(after: slashIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        if sizePart == "*" {
            return -1
        }
        return Int64(sizePart)
    }
}

// MARK: - Filename Resolution

public enum FilenameResolver: Sendable {
    public static func resolve(contentDisposition: String?, finalURL: URL) -> String {
        if let disposition = contentDisposition,
           let filename = parseContentDisposition(disposition),
           !filename.isEmpty {
            return filename
        }
        return fallbackFilename(from: finalURL)
    }

    public static func parseContentDisposition(_ header: String) -> String? {
        // 1. Try RFC 5987: filename*=UTF-8''... (higher precedence per RFC 6266)
        if let rfcFilename = parseRFC5987(header) {
            let sanitized = sanitize(rfcFilename)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        // 2. Try standard filename="foo.zip"
        if let standardFilename = parseStandard(header) {
            let sanitized = sanitize(standardFilename)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        return nil
    }

    private static func parseRFC5987(_ header: String) -> String? {
        // Matches case-insensitive filename*=
        guard let range = header.range(of: "filename\\*\\s*=\\s*", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        var remaining = String(header[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        // If quoted, extract quoted portion
        if remaining.hasPrefix("\"") {
            let withoutLeadingQuote = remaining.dropFirst()
            if let closingQuoteIndex = withoutLeadingQuote.firstIndex(of: "\"") {
                remaining = String(withoutLeadingQuote[..<closingQuoteIndex])
            }
        } else {
            if let semicolonIndex = remaining.firstIndex(of: ";") {
                remaining = String(remaining[..<semicolonIndex]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Syntax: charset'language'encoded-value
        let parts = remaining.components(separatedBy: "'")
        guard parts.count >= 3 else {
            return remaining.removingPercentEncoding
        }

        let encodedValue = parts.dropFirst(2).joined(separator: "'")
        return encodedValue.removingPercentEncoding
    }

    private static func parseStandard(_ header: String) -> String? {
        // Matches filename=, but avoids filename*=
        guard let range = header.range(of: "(?:^|[;\\s])filename\\s*=\\s*", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let remaining = String(header[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if remaining.hasPrefix("\"") {
            let withoutLeading = remaining.dropFirst()
            var result = ""
            var isEscaping = false
            for char in withoutLeading {
                if isEscaping {
                    result.append(char)
                    isEscaping = false
                } else if char == "\\" {
                    isEscaping = true
                } else if char == "\"" {
                    break
                } else {
                    result.append(char)
                }
            }
            return result
        } else {
            let raw = remaining.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return raw.isEmpty ? nil : raw
        }
    }

    public static func fallbackFilename(from url: URL) -> String {
        var pathComponent = url.lastPathComponent
        if let decoded = pathComponent.removingPercentEncoding, !decoded.isEmpty {
            pathComponent = decoded
        }
        let sanitized = sanitize(pathComponent)
        if sanitized.isEmpty || sanitized == "/" || sanitized == "." {
            return "download"
        }
        return sanitized
    }

    public static func sanitize(_ filename: String) -> String {
        var name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "\0", with: "")
        name = name.replacingOccurrences(of: "\\", with: "/")

        if let last = name.split(separator: "/").last {
            name = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            name = ""
        }

        if name == "." || name == ".." || name == "/" {
            return ""
        }

        return name
    }
}
