//
//  LocalhostBridge.swift
//  DownloadKit
//
//  Created by HyperFetch on 2026-11-02.
//

import Foundation
import Network

/// Represents errors that can occur while managing the localhost HTTP bridge.
public enum LocalhostBridgeError: Error, LocalizedError, Sendable {
    case listenerCreationFailed(String)
    case portBindingFailed(ports: [UInt16])
    case bridgeAlreadyRunning
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .listenerCreationFailed(let message):
            return "Failed to create localhost bridge listener: \(message)"
        case .portBindingFailed(let ports):
            return "Failed to bind localhost bridge to any available ports: \(ports)"
        case .bridgeAlreadyRunning:
            return "Localhost bridge is already running."
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        }
    }
}

/// Represents a structured download request received via HTTP.
public struct DownloadRequest: Codable, Sendable {
    public let url: String
    public let filename: String?
    public let autoStart: Bool?
    public let headers: [String: String]?

    public init(url: String, filename: String? = nil, autoStart: Bool? = nil, headers: [String: String]? = nil) {
        self.url = url
        self.filename = filename
        self.autoStart = autoStart
        self.headers = headers
    }

    enum CodingKeys: String, CodingKey {
        case url, filename, autoStart, headers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.filename = try container.decodeIfPresent(String.self, forKey: .filename)
        if let boolVal = try? container.decodeIfPresent(Bool.self, forKey: .autoStart) {
            self.autoStart = boolVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .autoStart) {
            self.autoStart = (strVal.lowercased() != "false" && strVal != "0")
        } else {
            self.autoStart = nil
        }
        self.headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
    }
}

/// A lightweight, embedded HTTP bridge that listens on loopback (127.0.0.1:31415 with fallback to 31416).
///
/// It allows browser extensions, bookmarklets, and local CLI tools to communicate with HyperFetch
/// and submit new download tasks seamlessly.
public final class LocalhostBridge: @unchecked Sendable {
    public typealias DownloadHandler = @Sendable (
        _ url: URL,
        _ filename: String?,
        _ autoStart: Bool,
        _ headers: [String: String]?
    ) -> Void
    public typealias SheetHandler = @Sendable (_ url: String?, _ filename: String?) -> Void
    public typealias ThemeHandler = @Sendable (_ mode: String) -> Void

    public let preferredPort: UInt16
    public let fallbackPort: UInt16
    public let bridgeToken: String?
    private let lock = NSLock()
    private var _onDownloadRequested: DownloadHandler?
    private var _onSheetRequested: SheetHandler?
    private var _onAppearanceChangeRequested: ThemeHandler?

    public var onDownloadRequested: DownloadHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onDownloadRequested
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onDownloadRequested = newValue
        }
    }

    public var onSheetRequested: SheetHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onSheetRequested
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onSheetRequested = newValue
        }
    }

    public var onAppearanceChangeRequested: ThemeHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onAppearanceChangeRequested
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onAppearanceChangeRequested = newValue
        }
    }

    private let queue = DispatchQueue(label: "com.hyperfetch.localhostbridge", qos: .userInitiated)
    private var listener: NWListener?
    private var currentPort: UInt16?
    private var activeConnections: Set<ObjectIdentifier> = []
    private var connectionMap: [ObjectIdentifier: NWConnection] = [:]

    /// Whether the bridge is currently active and listening.
    public var isRunning: Bool {
        queue.sync {
            listener != nil && currentPort != nil
        }
    }

    /// The active listening port, or `nil` if not running.
    public var listeningPort: UInt16? {
        queue.sync { currentPort }
    }

    public init(
        preferredPort: UInt16 = 31415,
        fallbackPort: UInt16 = 31416,
        bridgeToken: String? = nil,
        onDownloadRequested: DownloadHandler? = nil
    ) {
        self.preferredPort = preferredPort
        self.fallbackPort = fallbackPort
        self.bridgeToken = bridgeToken
        self.onDownloadRequested = onDownloadRequested
    }

    deinit {
        stop()
    }

    /// Starts the localhost bridge, attempting the preferred port first, then falling back if busy.
    /// Returns the port on which the bridge is listening.
    @discardableResult
    public func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.listener != nil, let port = self.currentPort {
                    continuation.resume(returning: port)
                    return
                }

                let context = StartContext { result in
                    continuation.resume(with: result)
                }
                self.attemptStart(ports: [self.preferredPort, self.fallbackPort], context: context)
            }
        }
    }

    /// Stops the localhost bridge and closes all active connections.
    public func stop() {
        queue.sync {
            for (_, connection) in self.connectionMap {
                connection.cancel()
            }
            self.connectionMap.removeAll()
            self.activeConnections.removeAll()

            if let l = self.listener {
                l.stateUpdateHandler = nil
                l.newConnectionHandler = nil
                l.cancel()
                self.listener = nil
            }
            self.currentPort = nil
        }
    }

    // MARK: - Port Binding & Listener Setup

    private final class StartContext: @unchecked Sendable {
        private let lock = NSLock()
        private var hasResumed = false
        private var completion: (@Sendable (Result<UInt16, any Error>) -> Void)?

        init(completion: @escaping @Sendable (Result<UInt16, any Error>) -> Void) {
            self.completion = completion
        }

        func complete(with result: Result<UInt16, any Error>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return false }
            hasResumed = true
            let comp = completion
            completion = nil
            comp?(result)
            return true
        }
    }

    private func attemptStart(
        ports: [UInt16],
        context: StartContext
    ) {
        guard let portToTry = ports.first else {
            _ = context.complete(with: .failure(LocalhostBridgeError.portBindingFailed(ports: [preferredPort, fallbackPort])))
            return
        }

        let remainingPorts = Array(ports.dropFirst())

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: portToTry) else {
                attemptStart(ports: remainingPorts, context: context)
                return
            }

            let tcpOptions = NWProtocolTCP.Options()
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true

            let newListener = try NWListener(using: parameters, on: nwPort)

            newListener.newConnectionHandler = { [weak self, weak newListener] connection in
                guard let self = self, let newListener = newListener, self.listener === newListener else {
                    connection.cancel()
                    return
                }
                self.handleIncomingConnection(connection)
            }

            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self = self, let newListener = newListener else { return }

                switch state {
                case .ready:
                    self.queue.async {
                        if context.complete(with: .success(portToTry)) {
                            self.listener = newListener
                            self.currentPort = portToTry
                        }
                    }

                case .failed:
                    self.queue.async {
                        newListener.cancel()
                        // Try next port if context hasn't resumed yet
                        self.attemptStart(ports: remainingPorts, context: context)
                    }

                case .cancelled:
                    break

                default:
                    break
                }
            }

            newListener.start(queue: queue)
        } catch {
            attemptStart(ports: remainingPorts, context: context)
        }
    }

    // MARK: - Connection Handling

    private func handleIncomingConnection(_ connection: NWConnection) {
        let connId = ObjectIdentifier(connection)
        connectionMap[connId] = connection
        activeConnections.insert(connId)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed, .cancelled:
                self.queue.async {
                    self.connectionMap.removeValue(forKey: connId)
                    self.activeConnections.remove(connId)
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
        readRequest(from: connection, accumulatedData: Data())
    }

    private func readRequest(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let connection = connection else { return }

            if error != nil {
                self.closeConnection(connection)
                return
            }

            var currentData = accumulatedData
            if let data = data {
                currentData.append(data)
            }

            // Check if full HTTP header delimiter \r\n\r\n is reached
            if let headerEndIndex = self.findHeaderEnd(in: currentData) {
                let headerData = currentData.subdata(in: 0..<headerEndIndex)
                let bodyData = currentData.subdata(in: headerEndIndex + 4..<currentData.count)

                let contentLength = self.parseContentLength(from: headerData)

                if bodyData.count >= contentLength {
                    // Full body received
                    self.processHTTPRequest(
                        headerData: headerData,
                        bodyData: bodyData.subdata(in: 0..<contentLength),
                        connection: connection
                    )
                } else if isComplete {
                    // Stream closed before content length reached
                    self.sendErrorResponse(status: 400, message: "Incomplete HTTP body", connection: connection)
                } else {
                    // Continue receiving body
                    self.readRequest(from: connection, accumulatedData: currentData)
                }
            } else if isComplete {
                self.closeConnection(connection)
            } else {
                // Keep reading headers
                self.readRequest(from: connection, accumulatedData: currentData)
            }
        }
    }

    private func findHeaderEnd(in data: Data) -> Int? {
        let delimiter = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        guard let range = data.range(of: delimiter) else { return nil }
        return range.lowerBound
    }

    private func parseContentLength(from headerData: Data) -> Int {
        guard let headerString = String(data: headerData, encoding: .utf8) else { return 0 }
        for line in headerString.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame {
                return Int(parts[1]) ?? 0
            }
        }
        return 0
    }

    // MARK: - HTTP Request Processing

    private func processHTTPRequest(headerData: Data, bodyData: Data, connection: NWConnection) {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            sendErrorResponse(status: 400, message: "Invalid UTF-8 request", connection: connection)
            return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            sendErrorResponse(status: 400, message: "Empty request line", connection: connection)
            return
        }

        let requestParts = requestLine.split(separator: " ").map(String.init)
        guard requestParts.count >= 2 else {
            sendErrorResponse(status: 400, message: "Malformed request line", connection: connection)
            return
        }

        let method = requestParts[0].uppercased()
        let target = requestParts[1]

        // Parse HTTP headers into lowercase dictionary for case-insensitive lookup
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1]
            }
        }

        // MARK: 1. Host Header Validation (DNS Rebinding Defense)
        guard let hostHeader = headers["host"], isAuthorizedHost(hostHeader) else {
            sendErrorResponse(
                status: 403,
                message: "Invalid or unauthorized Host header",
                connection: connection
            )
            return
        }

        // MARK: 2. Origin & Referer Validation (Safe CORS & CSRF Defense)
        var allowedOrigin: String? = nil
        if let origin = headers["origin"] {
            guard isAuthorizedOrigin(origin) else {
                sendErrorResponse(
                    status: 403,
                    message: "Cross-origin access from external web origin prohibited",
                    connection: connection
                )
                return
            }
            allowedOrigin = origin
        } else if let referer = headers["referer"] {
            guard isAuthorizedOrigin(referer) else {
                sendErrorResponse(
                    status: 403,
                    message: "Cross-origin access from external web origin prohibited",
                    connection: connection
                )
                return
            }
        }

        if let secFetchSite = headers["sec-fetch-site"], secFetchSite.lowercased() == "cross-site" {
            if allowedOrigin == nil {
                sendErrorResponse(
                    status: 403,
                    message: "Cross-origin access from external web origin prohibited",
                    connection: connection
                )
                return
            }
        }

        // Handle CORS Preflight OPTIONS
        if method == "OPTIONS" {
            sendCORSPreflightResponse(allowedOrigin: allowedOrigin, connection: connection)
            return
        }

        // Parse path and query
        guard let urlComponents = URLComponents(string: target) else {
            sendErrorResponse(status: 400, message: "Invalid request target", allowedOrigin: allowedOrigin, connection: connection)
            return
        }

        let path = urlComponents.path.lowercased()

        // MARK: 3. Client Identification & Shared Secret Authentication (CWE-346)
        guard isAuthorizedClient(headers: headers, method: method, path: path, origin: headers["origin"]) else {
            sendErrorResponse(
                status: 403,
                message: "Client authentication required: missing or invalid client token or header",
                allowedOrigin: allowedOrigin,
                connection: connection
            )
            return
        }

        switch (method, path) {
        case ("GET", "/status"), ("GET", "/"), ("GET", "/health"):
            let port = currentPort ?? preferredPort
            sendJSONResponse(
                status: 200,
                json: [
                    "status": "ok",
                    "app": "HyperFetch",
                    "version": "1.0.8",
                    "port": Int(port)
                ],
                allowedOrigin: allowedOrigin,
                connection: connection
            )

        case ("POST", "/add"), ("POST", "/download"):
            handlePostAdd(bodyData: bodyData, allowedOrigin: allowedOrigin, connection: connection)

        case ("GET", "/add"), ("GET", "/download"):
            handleGetAdd(queryItems: urlComponents.queryItems ?? [], allowedOrigin: allowedOrigin, connection: connection)

        case ("GET", "/sheet"), ("POST", "/sheet"):
            let queryDict = Dictionary((urlComponents.queryItems ?? []).compactMap { item in
                item.value != nil ? (item.name, item.value!) : nil
            }, uniquingKeysWith: { first, _ in first })
            let url = queryDict["url"]
            let filename = queryDict["filename"]
            onSheetRequested?(url, filename)
            sendJSONResponse(
                status: 200,
                json: ["status": "ok", "message": "Sheet requested"],
                allowedOrigin: allowedOrigin,
                connection: connection
            )

        case ("GET", "/theme"), ("POST", "/theme"):
            let queryDict = Dictionary((urlComponents.queryItems ?? []).compactMap { item in
                item.value != nil ? (item.name, item.value!) : nil
            }, uniquingKeysWith: { first, _ in first })
            let mode = queryDict["mode"] ?? "dark"
            onAppearanceChangeRequested?(mode)
            sendJSONResponse(
                status: 200,
                json: ["status": "ok", "theme": mode],
                allowedOrigin: allowedOrigin,
                connection: connection
            )

        default:
            sendErrorResponse(status: 404, message: "Route not found: \(path)", allowedOrigin: allowedOrigin, connection: connection)
        }
    }

    private func handlePostAdd(bodyData: Data, allowedOrigin: String?, connection: NWConnection) {
        guard !bodyData.isEmpty else {
            sendErrorResponse(status: 400, message: "Empty request body", allowedOrigin: allowedOrigin, connection: connection)
            return
        }

        guard let request = try? JSONDecoder().decode(DownloadRequest.self, from: bodyData),
              let url = URL(string: request.url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            sendErrorResponse(status: 400, message: "Missing or invalid 'url' parameter (must be http/https)", allowedOrigin: allowedOrigin, connection: connection)
            return
        }

        let sanitized = request.filename.map { FilenameResolver.sanitize($0) }
        let resolvedFilename = (sanitized?.isEmpty == false) ? sanitized : nil
        let autoStart = request.autoStart ?? true
        let headers = request.headers

        // Trigger download handler
        onDownloadRequested?(url, resolvedFilename, autoStart, headers)

        sendJSONResponse(
            status: 200,
            json: [
                "status": "ok",
                "message": "Download added to HyperFetch",
                "url": url.absoluteString,
                "filename": resolvedFilename as Any
            ],
            allowedOrigin: allowedOrigin,
            connection: connection
        )
    }

    private func handleGetAdd(queryItems: [URLQueryItem], allowedOrigin: String?, connection: NWConnection) {
        let queryDict = Dictionary(queryItems.compactMap { item in
            item.value != nil ? (item.name, item.value!) : nil
        }, uniquingKeysWith: { first, _ in first })

        guard let urlString = queryDict["url"],
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            sendErrorResponse(status: 400, message: "Missing or invalid 'url' query parameter", allowedOrigin: allowedOrigin, connection: connection)
            return
        }

        let sanitized = queryDict["filename"].map { FilenameResolver.sanitize($0) }
        let resolvedFilename = (sanitized?.isEmpty == false) ? sanitized : nil

        let autoStart: Bool
        if let autoParam = queryDict["autoStart"] {
            autoStart = (autoParam.lowercased() != "false" && autoParam != "0")
        } else {
            autoStart = true
        }

        var headers: [String: String]? = nil
        if let headersParam = queryDict["headers"],
           let data = headersParam.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            headers = parsed
        }

        // Trigger download handler
        onDownloadRequested?(url, resolvedFilename, autoStart, headers)

        sendJSONResponse(
            status: 200,
            json: [
                "status": "ok",
                "message": "Download added to HyperFetch",
                "url": url.absoluteString,
                "filename": resolvedFilename as Any
            ],
            allowedOrigin: allowedOrigin,
            connection: connection
        )
    }

    // MARK: - Security & Authorization Helpers

    /// Validates whether the incoming Host header represents a safe loopback address.
    /// Prevents DNS rebinding attacks where external hostnames resolve to 127.0.0.1.
    func isAuthorizedHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespaces).lowercased()
        if host == "127.0.0.1" || host == "localhost" {
            return true
        }
        let parts = host.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 {
            let hostname = parts[0]
            let portStr = parts[1]
            if (hostname == "127.0.0.1" || hostname == "localhost"), UInt16(portStr) != nil {
                return true
            }
        }
        return false
    }

    /// Validates whether an incoming Origin header belongs to an authorized browser extension or local origin.
    /// Blocks cross-origin access from external web domains (e.g., https://malicious.com).
    func isAuthorizedOrigin(_ rawOrigin: String) -> Bool {
        let lower = rawOrigin.trimmingCharacters(in: .whitespaces).lowercased()
        if isExtensionOrigin(lower) {
            return true
        }

        for prefix in ["http://127.0.0.1", "http://localhost", "https://127.0.0.1", "https://localhost"] {
            if lower == prefix {
                return true
            }
            if lower.hasPrefix(prefix + ":") || lower.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }

    /// Checks whether the raw origin represents a recognized browser extension scheme.
    func isExtensionOrigin(_ rawOrigin: String) -> Bool {
        let lower = rawOrigin.trimmingCharacters(in: .whitespaces).lowercased()
        return lower.hasPrefix("chrome-extension://") ||
               lower.hasPrefix("moz-extension://") ||
               lower.hasPrefix("safari-web-extension://")
    }

    /// Validates client identification and shared secret token authentication (CWE-346).
    /// Requires requests with extension Origin or state-modifying POST requests to supply proper identification.
    func isAuthorizedClient(
        headers: [String: String],
        method: String,
        path: String,
        origin: String?
    ) -> Bool {
        // 1. Shared secret token enforcement if configured on this bridge
        if let requiredToken = bridgeToken, !requiredToken.isEmpty {
            if let tokenHeader = headers["x-hyperfetch-token"], tokenHeader == requiredToken {
                return true
            }
            if let authHeader = headers["authorization"] {
                let trimmed = authHeader.replacingOccurrences(of: "Bearer ", with: "").trimmingCharacters(in: .whitespaces)
                if trimmed == requiredToken {
                    return true
                }
            }
            return false
        }

        // 2. Client identification check:
        // Any request with X-HyperFetch-Client: extension or an Authorization / Token header is authorized
        let hasClientHeader = headers["x-hyperfetch-client"]?.lowercased() == "extension"
        let hasAuth = headers["authorization"] != nil || headers["x-hyperfetch-token"] != nil

        if hasClientHeader || hasAuth {
            return true
        }

        // 3. Requests with Origin: chrome-extension://... (or other extension origins) MUST provide client identification
        if let origin = origin, isExtensionOrigin(origin) {
            return false
        }

        // 4. State-modifying POST requests MUST provide client identification
        if method == "POST" {
            return false
        }

        // Non-POST requests without extension origin (e.g. GET /status from local CLI or browser probe)
        return true
    }

    // MARK: - HTTP Responses

    private func sendCORSPreflightResponse(allowedOrigin: String?, connection: NWConnection) {
        var headerLines = [
            "HTTP/1.1 204 No Content"
        ]
        headerLines.append("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'")
        headerLines.append("X-Frame-Options: DENY")
        headerLines.append("X-Content-Type-Options: nosniff")
        headerLines.append("Referrer-Policy: no-referrer")
        if let allowedOrigin = allowedOrigin {
            headerLines.append("Access-Control-Allow-Origin: \(allowedOrigin)")
            headerLines.append("Vary: Origin")
        }
        headerLines.append(contentsOf: [
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-HyperFetch-Client, X-HyperFetch-Token",
            "Access-Control-Max-Age: 86400",
            "Content-Length: 0",
            "Connection: close",
            "",
            ""
        ])
        let responseString = headerLines.joined(separator: "\r\n")
        sendData(responseString.data(using: .utf8) ?? Data(), connection: connection)
    }

    private func sendJSONResponse(
        status: Int,
        json: [String: Any],
        allowedOrigin: String? = nil,
        connection: NWConnection
    ) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }
        let jsonData = (try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])) ?? Data("{}".utf8)

        var headerLines = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(jsonData.count)"
        ]

        headerLines.append("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'")
        headerLines.append("X-Frame-Options: DENY")
        headerLines.append("X-Content-Type-Options: nosniff")
        headerLines.append("Referrer-Policy: no-referrer")

        if let allowedOrigin = allowedOrigin {
            headerLines.append("Access-Control-Allow-Origin: \(allowedOrigin)")
            headerLines.append("Vary: Origin")
            headerLines.append("Access-Control-Allow-Methods: GET, POST, OPTIONS")
            headerLines.append("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-HyperFetch-Client, X-HyperFetch-Token")
        }

        headerLines.append("Connection: close")
        headerLines.append("")
        headerLines.append("")

        let headerString = headerLines.joined(separator: "\r\n")
        var fullData = headerString.data(using: .utf8) ?? Data()
        fullData.append(jsonData)

        sendData(fullData, connection: connection)
    }

    private func sendErrorResponse(
        status: Int,
        message: String,
        allowedOrigin: String? = nil,
        connection: NWConnection
    ) {
        sendJSONResponse(
            status: status,
            json: [
                "status": "error",
                "message": message
            ],
            allowedOrigin: allowedOrigin,
            connection: connection
        )
    }

    private func sendData(_ data: Data, connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed({ [weak self, weak connection] _ in
            guard let self = self, let connection = connection else { return }
            self.closeConnection(connection)
        }))
    }

    private func closeConnection(_ connection: NWConnection) {
        queue.async {
            let connId = ObjectIdentifier(connection)
            self.connectionMap.removeValue(forKey: connId)
            self.activeConnections.remove(connId)
            connection.cancel()
        }
    }
}
