# HyperFetch Functional Improvements — Implementation Plan

> **For implementors:** Use `subagent-driven-development` to execute task-by-task.

**Goal:** Fix all 20 findings from the functional review — engine correctness, performance, persistence efficiency, networking, security, and UI rendering.

**Architecture:** Changes are grouped into 8 independent tasks. Tasks 1–6 touch `Sources/DownloadKit` (pure Swift library, testable). Task 7 touches `Sources/HyperFetchApp` (UI layer). Task 8 is the Chrome extension (JavaScript). Each task has its own test coverage and commit.

**Tech Stack:** Swift 6, Swift Testing framework (`@Suite`/`@Test`), macOS 14+, No new dependencies.

**Test command:** `swift test` from `/opt/homebrew/var/www/FDM`

---

## Task 1 — DownloadEngine: Extract cancellation helper & fix 403/503 error classification

**Files:**
- Modify: `Sources/DownloadKit/Engine/DownloadEngine.swift`
- Modify: `Tests/DownloadKitTests/DownloadEngineTests.swift`

### Context

Finding 1.1: The same 8-line cancel+persist+throw block is duplicated ~10 times.  
Finding 1.3: HTTP 403 and 503 are misclassified as "range not supported" — this resets `downloadedBytes = 0` and retries as a single stream, losing resume progress.

Current (wrong) behaviour:
```swift
// In isRangeNotSupportedError:
case .httpError(let statusCode):
    return statusCode == 416 || statusCode == 501 || statusCode == 429 || statusCode == 403 || statusCode == 503
```

A `403` means auth failure — retrying without ranges will also fail.  
A `503` is transient — back off and retry, keeping `supportsRange = true`.  
Only `416` and `501` are true "range not supported" signals.

### Step 1: Write failing tests

Add to `Tests/DownloadKitTests/DownloadEngineTests.swift`:

```swift
// MARK: - Error Classification Tests

@Test("isRangeNotSupportedError returns true only for 416 and 501")
func testErrorClassification_rangeErrors() async throws {
    let engine = DownloadEngine()
    // 416 = Range Not Satisfiable → true
    let err416 = ChunkDownloadError.httpError(statusCode: 416)
    #expect(engine.exposedIsRangeNotSupportedError(err416) == true)
    // 501 = Not Implemented → true
    let err501 = ChunkDownloadError.httpError(statusCode: 501)
    #expect(engine.exposedIsRangeNotSupportedError(err501) == true)
    // 403 = Forbidden → false (should NOT fall back to single-stream)
    let err403 = ChunkDownloadError.httpError(statusCode: 403)
    #expect(engine.exposedIsRangeNotSupportedError(err403) == false)
    // 503 = Service Unavailable → false (transient, not a range issue)
    let err503 = ChunkDownloadError.httpError(statusCode: 503)
    #expect(engine.exposedIsRangeNotSupportedError(err503) == false)
    // 429 = Too Many Requests → false (rate limit, not range issue)
    let err429 = ChunkDownloadError.httpError(statusCode: 429)
    #expect(engine.exposedIsRangeNotSupportedError(err429) == false)
}

@Test("isRateLimitError returns true for 429 and 503")
func testErrorClassification_rateLimitErrors() async throws {
    let engine = DownloadEngine()
    let err429 = ChunkDownloadError.httpError(statusCode: 429)
    #expect(engine.exposedIsRateLimitError(err429) == true)
    let err503 = ChunkDownloadError.httpError(statusCode: 503)
    #expect(engine.exposedIsRateLimitError(err503) == true)
    let err403 = ChunkDownloadError.httpError(statusCode: 403)
    #expect(engine.exposedIsRateLimitError(err403) == false)
}
```

Also add a test that a 403 from the server surfaces as `.failed`, not as a single-stream retry. Use the existing mock URL protocol pattern in `DownloadEngineTests.swift`.

### Step 2: Run tests to confirm they fail

```bash
cd /opt/homebrew/var/www/FDM
swift test --filter "DownloadEngineTests/testErrorClassification" 2>&1
```
Expected: compile error (methods not `internal`/`public`) or test failure.

### Step 3: Implement changes in `DownloadEngine.swift`

**3a. Extract the cancellation helper.** Add this private method to `DownloadEngine`:

```swift
/// Shared cancellation teardown — syncs + closes writer, marks task paused, persists, notifies handler, then throws.
private func cancelAndPause(
    task: inout DownloadTaskModel,
    writer: any FileWriting,
    progressHandler: (@Sendable (DownloadTaskModel) -> Void)?
) async throws -> Never {
    try? await writer.sync()
    await writer.close()
    // Pull latest engine state (chunks may have advanced)
    if let latest = taskStore[task.id] { task = latest }
    task.status = .paused
    task.bytesPerSecond = 0.0
    taskStore[task.id] = task
    try? await statePersister?.saveTask(task)
    progressHandler?(task)
    throw CancellationError()
}
```

**3b. Replace every duplicated cancel block** throughout `startDownload` and `executeChunks` with:

```swift
try await cancelAndPause(task: &currentTask, writer: writer, progressHandler: progressHandler)
```

There are approximately 10 occurrences. Replace every one.

**3c. Fix `isRangeNotSupportedError`** — remove 403, 429, 503 from the range-unsupported list:

```swift
private func isRangeNotSupportedError(_ error: Error) -> Bool {
    if let chunkError = error as? ChunkDownloadError {
        switch chunkError {
        case .serverDoesNotSupportRange:
            return true
        case .httpError(let statusCode):
            // Only true "range not supported" codes
            return statusCode == 416 || statusCode == 501
        default:
            break
        }
    }
    let desc = error.localizedDescription
    // Keep string-based detection for edge cases, but remove 429/403/503
    return desc.contains("206") || desc.contains("range") || desc.contains("Range")
}
```

**3d. Add `@testable` exposure** — temporarily make `isRangeNotSupportedError` and `isRateLimitError` `internal` (they already are; actors expose internal methods to `@testable import`). Add wrapper methods for testing:

```swift
// In DownloadEngine — only compiled in test builds
func exposedIsRangeNotSupportedError(_ error: Error) -> Bool {
    isRangeNotSupportedError(error)
}
func exposedIsRateLimitError(_ error: Error) -> Bool {
    isRateLimitError(error)
}
```

### Step 4: Run tests to confirm they pass

```bash
swift test --filter "DownloadEngineTests" 2>&1
```
Expected: all pass, no regressions.

### Step 5: Commit

```bash
git add Sources/DownloadKit/Engine/DownloadEngine.swift \
        Tests/DownloadKitTests/DownloadEngineTests.swift
git commit -m "fix(engine): extract cancelAndPause helper, fix 403/503 error classification

- Deduplicates ~10 identical cancel-teardown blocks into cancelAndPause()
- Removes 403, 429, 503 from isRangeNotSupportedError — only 416/501 are true
  range-not-supported signals; 429/503 remain rate-limit signals
- 403 now surfaces as .failed instead of triggering single-stream fallback"
```

---

## Task 2 — StatePersister: Debounce writes + compact JSON encoding

**Files:**
- Modify: `Sources/DownloadKit/Storage/StatePersister.swift`
- Modify: `Tests/DownloadKitTests/StatePersistenceTests.swift`

### Context

Finding 3.1: `saveTask` re-encodes and writes **all tasks** to disk on every 100 ms progress tick — up to 80 full-file writes/second.  
Finding 3.3: `JSONEncoder` uses `.prettyPrinted`, making files 2–4× larger and slower.

The fix: add write debouncing inside the actor so that progress-tick saves are coalesced into at most one write per 500 ms. Status-transition saves (paused, completed, failed) always flush immediately.

### Step 1: Write failing tests

Add to `Tests/DownloadKitTests/StatePersistenceTests.swift`:

```swift
@Test("saveTask debounces rapid progress saves — only one disk write per 500ms window")
func testSaveTask_debouncesRapidWrites() async throws {
    let dir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let storageURL = dir.appendingPathComponent("state.json")
    let persister = JSONStatePersister(storageURL: storageURL)

    var task = DownloadTaskModel(url: URL(string: "https://example.com/file.zip")!)

    // Fire 10 rapid progress saves — should coalesce to 1 disk write
    for i in 0..<10 {
        task.downloadedBytes = Int64(i * 1024)
        try await persister.saveTask(task, immediate: false)
    }
    // Flush
    try await persister.flush()

    let onDisk = try await persister.load()
    #expect(onDisk.count == 1)
    #expect(onDisk[0].downloadedBytes == 9 * 1024)
}

@Test("saveTask with immediate=true flushes to disk without delay")
func testSaveTask_immediateFlushesInstantly() async throws {
    let dir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let storageURL = dir.appendingPathComponent("state.json")
    let persister = JSONStatePersister(storageURL: storageURL)

    let task = DownloadTaskModel(url: URL(string: "https://example.com/file.zip")!)
    try await persister.saveTask(task, immediate: true)

    // Should be on disk immediately (no debounce)
    #expect(FileManager.default.fileExists(atPath: storageURL.path))
}

@Test("JSON state file uses compact encoding (no pretty-print)")
func testCompactEncoding() async throws {
    let dir = try createTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let storageURL = dir.appendingPathComponent("state.json")
    let persister = JSONStatePersister(storageURL: storageURL)

    let task = DownloadTaskModel(url: URL(string: "https://example.com/file.zip")!)
    try await persister.saveTask(task, immediate: true)

    let raw = try String(contentsOf: storageURL, encoding: .utf8)
    // Compact JSON has no newlines outside of string values
    #expect(!raw.contains("\n  ")) // no pretty-print indentation
}
```

### Step 2: Run tests to confirm they fail

```bash
swift test --filter "StatePersistenceTests/testSaveTask_debounces" 2>&1
```

### Step 3: Implement in `StatePersister.swift`

**3a. Add `immediate` parameter to `saveTask`** and add a debounce task:

```swift
public actor JSONStatePersister: StatePersisting {
    // ... existing properties ...
    private var pendingDebounceTask: Task<Void, Never>?
    private let debounceInterval: Duration

    public init(
        storageURL: URL = JSONStatePersister.defaultStorageURL,
        fileManager: FileManager = .default,
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        self.debounceInterval = debounceInterval
    }

    /// Updates or inserts a single task.
    /// - Parameter immediate: When true (status transitions), writes synchronously.
    ///   When false (progress updates), coalesces within the debounce window.
    public func saveTask(_ task: DownloadTaskModel, immediate: Bool = false) async throws {
        var currentTasks = cachedTasks ?? loadRawTasks()
        if let index = currentTasks.firstIndex(where: { $0.id == task.id }) {
            currentTasks[index] = task
        } else {
            currentTasks.append(task)
        }
        cachedTasks = currentTasks

        if immediate {
            pendingDebounceTask?.cancel()
            pendingDebounceTask = nil
            try await save(tasks: currentTasks)
        } else {
            pendingDebounceTask?.cancel()
            let tasks = currentTasks
            pendingDebounceTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: self?.debounceInterval ?? .milliseconds(500))
                    try? await self?.save(tasks: tasks)
                } catch {
                    // Cancelled — a newer save will follow
                }
            }
        }
    }

    /// Forces any pending debounced write to flush immediately.
    public func flush() async throws {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil
        if let tasks = cachedTasks {
            try await save(tasks: tasks)
        }
    }
}
```

**3b. Update the `StatePersisting` protocol** to add `flush()` and the `immediate` parameter:

```swift
public protocol StatePersisting: Sendable {
    func save(tasks: [DownloadTaskModel]) async throws
    func load() async throws -> [DownloadTaskModel]
    func saveTask(_ task: DownloadTaskModel, immediate: Bool) async throws
    func deleteTask(id: UUID) async throws
    func flush() async throws
}

extension StatePersisting {
    // Default: backward-compat — immediate = true preserves existing callers
    public func saveTask(_ task: DownloadTaskModel) async throws {
        try await saveTask(task, immediate: true)
    }
}
```

**3c. Update `DownloadEngine`** to pass `immediate: false` for in-flight progress saves and `immediate: true` for status transitions (paused, completed, failed):

In `DownloadEngine.swift`, find every `try? await statePersister?.saveTask(...)` call and change:
- Inside `recordChunkProgress` → `saveTask(task, immediate: false)` (this is the hot path)
- In `cancelAndPause` → `saveTask(task, immediate: true)`  
- In `startDownload` on `.completed` → `saveTask(task, immediate: true)`
- In `startDownload` on `.failed` → `saveTask(task, immediate: true)`

**3d. Remove `.prettyPrinted` from `makeEncoder()`:**

```swift
private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    // .sortedKeys is kept for deterministic diffing in tests; remove .prettyPrinted
    encoder.outputFormatting = .sortedKeys
    return encoder
}
```

### Step 4: Run tests

```bash
swift test --filter "StatePersistenceTests" 2>&1
```

### Step 5: Commit

```bash
git add Sources/DownloadKit/Storage/StatePersister.swift \
        Sources/DownloadKit/Engine/DownloadEngine.swift \
        Tests/DownloadKitTests/StatePersistenceTests.swift
git commit -m "perf(persister): debounce progress saves (500ms), compact JSON encoding

- saveTask(immediate: false) coalesces rapid progress updates into one write
- Status transitions (paused, completed, failed) still flush immediately
- Removes .prettyPrinted — compact JSON is 2-4x smaller and faster to encode
- Adds flush() to StatePersisting protocol for deterministic test teardown"
```

---

## Task 3 — QueueManager: O(1) task lookup + correct concurrency-reduce pause order

**Files:**
- Modify: `Sources/DownloadKit/Engine/QueueManager.swift`
- Modify: `Tests/DownloadKitTests/QueueManagerTests.swift`

### Context

Finding 2.1: `taskQueue.first(where: { $0.id == id })` is O(n) on every call. Called frequently during active downloads from progress handlers, completion handlers, etc.  
Finding 2.2: When reducing max concurrent downloads, the code pauses tasks in reversed queue order — meaning the user's first (highest-priority) task gets paused instead of the last-added task.

### Step 1: Write failing tests

Add to `Tests/DownloadKitTests/QueueManagerTests.swift`:

```swift
@Test("setMaxConcurrentDownloads pauses last-added tasks, not first-added")
func testReducingConcurrency_pausesLowerPriorityTasksFirst() async throws {
    // Start 3 downloads, then reduce to 1 — tasks 2 and 3 should be paused, not task 1
    let qm = QueueManager(maxConcurrentDownloads: 3)
    // ... use mock engine / probes ...
    // Add 3 tasks
    // Reduce to 1
    // Assert task[0] is still downloading
    // Assert task[1] and task[2] are paused
}

@Test("task(for:) returns correct task with many items in queue")
func testTaskLookup_correctWithManyTasks() async throws {
    let qm = QueueManager(maxConcurrentDownloads: 1)
    var ids: [UUID] = []
    for i in 0..<50 {
        let url = URL(string: "https://example.com/file\(i).zip")!
        let task = try await qm.addTask(url: url, autoStart: false)
        ids.append(task.id)
    }
    // Look up the last-added task — previously O(n), now O(1)
    let found = await qm.task(for: ids.last!)
    #expect(found != nil)
    #expect(found?.url.absoluteString == "https://example.com/file49.zip")
}
```

### Step 2: Run tests

```bash
swift test --filter "QueueManagerTests/testReducingConcurrency" 2>&1
```

### Step 3: Implement in `QueueManager.swift`

**3a. Add an index dictionary** (no new dependencies — just a parallel `[UUID: Int]`):

```swift
// Add alongside taskQueue:
private var taskIndexMap: [UUID: Int] = [:]

// Add a helper to rebuild the index:
private func rebuildIndex() {
    taskIndexMap.removeAll(minimumCapacity: taskQueue.count)
    for (i, task) in taskQueue.enumerated() {
        taskIndexMap[task.id] = i
    }
}
```

**3b. Update all mutations** to maintain the index:
- After `taskQueue.append(task)`: `taskIndexMap[task.id] = taskQueue.count - 1`
- After `taskQueue.remove(at: idx)`: call `rebuildIndex()` (removals invalidate all subsequent indices)
- After `taskQueue.insert(task, at:)`: call `rebuildIndex()`

**3c. Replace the linear scans** in `task(for:)` and everywhere `taskQueue.firstIndex(where: { $0.id == id })` is used:

```swift
public func task(for id: UUID) -> DownloadTaskModel? {
    guard let idx = taskIndexMap[id] else { return nil }
    return taskQueue[idx]
}

// Helper used internally:
private func taskIndex(for id: UUID) -> Int? { taskIndexMap[id] }
```

**Note:** `rebuildIndex()` is O(n) but called only on structural changes (add/remove/reorder), not on every lookup or progress update. All existing `firstIndex(where:)` calls should be replaced with `taskIndex(for:)` to get O(1) everywhere.

**3d. Fix `setMaxConcurrentDownloads` pause order** — pause from the _end_ of the active set (lowest priority, last added) instead of reversed queue order:

```swift
// WRONG (current):
if let taskToPause = taskQueue.reversed().first(where: { activeTasks[$0.id] != nil }) {

// CORRECT (last-added active task = iterate forward, take the last match):
if let taskToPause = taskQueue.last(where: { activeTasks[$0.id] != nil }) {
```

### Step 4: Run tests

```bash
swift test --filter "QueueManagerTests" 2>&1
```

### Step 5: Commit

```bash
git add Sources/DownloadKit/Engine/QueueManager.swift \
        Tests/DownloadKitTests/QueueManagerTests.swift
git commit -m "perf(queue): O(1) task lookup via index map, fix concurrency-reduce pause order

- taskIndexMap[UUID] replaces linear firstIndex(where:) scans
- setMaxConcurrentDownloads now pauses last-added (lowest priority) tasks
  instead of first-added (highest priority) tasks"
```

---

## Task 4 — HTTPRangeProbe: Parallel HEAD + Range GET probes + retry jitter

**Files:**
- Modify: `Sources/DownloadKit/Network/HTTPRangeProbe.swift`
- Modify: `Sources/DownloadKit/Network/ChunkDownloader.swift`
- Modify: `Tests/DownloadKitTests/HTTPRangeProbeTests.swift`
- Modify: `Tests/DownloadKitTests/ChunkDownloaderTests.swift`

### Context

Finding 4.1: Probe fires HEAD → GET bytes=0-0 → plain GET sequentially. For servers that always return 200 to HEAD, every download needs 2 round trips before data flows.  
Finding 4.2: Chunk retry backoff has no jitter — 8 chunks all retry at the same instant, causing a thundering herd.

### Step 1: Write failing tests

In `Tests/DownloadKitTests/HTTPRangeProbeTests.swift`:

```swift
@Test("probe issues HEAD and GET range in parallel when HEAD returns non-definitive result")
func testProbe_parallelRequests() async throws {
    // Set up mock: HEAD returns 200 without Accept-Ranges header (forces GET probe)
    // Track request timing — both should start within 50ms of each other
    // ... use existing ProbeMockURLProtocol pattern ...
    var requestTimes: [String: Date] = [:]
    // Register handlers that record timestamps
    // Run probe
    // Assert both HEAD and GET requests fired within 100ms of each other
}

@Test("ChunkDownloader retry uses jitter between attempts")
func testChunkDownloader_retryJitter() async throws {
    // Set up server that fails twice then succeeds
    // Record the sleep intervals between attempts
    // Assert the sleep times differ by at least 10ms (jitter present)
    // This is tricky to test directly — test indirectly via timing or mock clock
}
```

### Step 2: Implement parallel probe in `HTTPRangeProbe.swift`

Replace `performHeadProbe` to fire HEAD and GET `bytes=0-0` in parallel when HEAD doesn't give a definitive answer:

```swift
public func probe(url: URL, headers: [String: String] = [:]) async throws -> ProbeResult {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        throw ProbeError.invalidURL(url)
    }

    do {
        // Fire HEAD and Range-GET in parallel
        async let headResult = performHeadProbe(url: url, headers: headers)
        async let rangeResult = performGetRangeProbe(url: url, headers: headers, headResponse: nil)

        // HEAD probe decides which result to use
        // If HEAD succeeds with range info → use it, cancel range probe
        // If HEAD is ambiguous → await rangeResult
        do {
            let head = try await headResult
            // HEAD gave us a definitive range-capable answer
            if head.supportsRange && head.totalBytes > 0 {
                return head
            }
            // HEAD wasn't definitive — wait for range probe
            return try await rangeResult
        } catch {
            // HEAD failed — use the range probe result
            return try await rangeResult
        }
    } catch is CancellationError {
        throw ProbeError.cancelled
    } catch let urlError as URLError where urlError.code == .cancelled {
        throw ProbeError.cancelled
    } catch let error as ProbeError {
        throw error
    } catch {
        throw ProbeError.networkError(error.localizedDescription)
    }
}
```

> **Note:** `async let` in Swift fires both tasks immediately. The key insight is that `await headResult` suspends, but `rangeResult` is already in-flight. When HEAD resolves definitively, `rangeResult` continues running in the background but is implicitly cancelled when it goes out of scope (Swift structured concurrency). This achieves "fire-and-cancel-on-first-win" without manual task management.

### Step 3: Add retry jitter in `ChunkDownloader.swift`

Find the retry sleep:
```swift
// BEFORE:
try await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000))

// AFTER:
let jitterNs = UInt64.random(in: 0..<200_000_000) // 0–200ms jitter
try await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000) + jitterNs)
```

One-line change. No test infrastructure needed — the existing `ChunkDownloaderTests` cover retry behaviour.

### Step 4: Run tests

```bash
swift test --filter "HTTPRangeProbeTests" 2>&1
swift test --filter "ChunkDownloaderTests" 2>&1
```

### Step 5: Commit

```bash
git add Sources/DownloadKit/Network/HTTPRangeProbe.swift \
        Sources/DownloadKit/Network/ChunkDownloader.swift \
        Tests/DownloadKitTests/HTTPRangeProbeTests.swift
git commit -m "perf(probe): parallel HEAD + range GET, add retry jitter

- async let fires HEAD and GET bytes=0-0 simultaneously; first definitive
  result wins — halves probe latency for servers that ignore HEAD
- Chunk retry backoff adds 0-200ms jitter to prevent thundering herd"
```

---

## Task 5 — LocalhostBridge: Request body size cap + dynamic version string

**Files:**
- Modify: `Sources/DownloadKit/Network/LocalhostBridge.swift`
- Modify: `Tests/DownloadKitTests/LocalhostBridgeTests.swift`

### Context

Finding 5.1: `readRequest` accumulates incoming data unboundedly. A malformed request body with no `\r\n\r\n` grows memory without limit until the connection drops.  
Finding 5.2: The `/status` endpoint returns `"version": "1.1.4"` hardcoded — drifts from the actual release version on every update.

### Step 1: Write failing tests

In `Tests/DownloadKitTests/LocalhostBridgeTests.swift`:

```swift
@Test("Bridge returns 413 for requests exceeding 1MB body limit")
func testBridge_rejectsOversizedBody() async throws {
    let bridge = LocalhostBridge(preferredPort: 31420)
    let port = try await bridge.start()
    defer { bridge.stop() }

    // Send a 2MB POST body
    let bigBody = Data(repeating: 0x41, count: 2 * 1024 * 1024) // 2MB of 'A'
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/add")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("\(bigBody.count)", forHTTPHeaderField: "Content-Length")
    req.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
    req.httpBody = bigBody

    let (_, response) = try await URLSession.shared.data(for: req)
    let httpResponse = response as! HTTPURLResponse
    #expect(httpResponse.statusCode == 413)
}

@Test("Bridge /status version matches injected version string")
func testBridge_statusReturnsInjectedVersion() async throws {
    let bridge = LocalhostBridge(preferredPort: 31421, version: "2.0.0")
    let port = try await bridge.start()
    defer { bridge.stop() }

    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
    req.setValue("extension", forHTTPHeaderField: "X-HyperFetch-Client")
    let (data, _) = try await URLSession.shared.data(for: req)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["version"] as? String == "2.0.0")
}
```

### Step 2: Implement in `LocalhostBridge.swift`

**2a. Add `version` parameter to init:**

```swift
public init(
    preferredPort: UInt16 = 31415,
    fallbackPort: UInt16 = 31416,
    bridgeToken: String? = nil,
    version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
    onDownloadRequested: DownloadHandler? = nil
) {
    self.preferredPort = preferredPort
    self.fallbackPort = fallbackPort
    self.bridgeToken = bridgeToken
    self.version = version
    self.onDownloadRequested = onDownloadRequested
}

private let version: String
```

Update the `/status` response to use `self.version`:
```swift
case ("GET", "/status"), ("GET", "/"), ("GET", "/health"):
    let port = currentPort ?? preferredPort
    sendJSONResponse(
        status: 200,
        json: ["status": "ok", "app": "HyperFetch", "version": version, "port": Int(port)],
        allowedOrigin: allowedOrigin,
        connection: connection
    )
```

**2b. Add a `maxRequestBodyBytes` constant and enforce it in `readRequest`:**

```swift
private let maxRequestBodyBytes = 1 * 1024 * 1024 // 1 MB

private func readRequest(from connection: NWConnection, accumulatedData: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
        guard let self, let connection else { return }

        if error != nil { self.closeConnection(connection); return }

        var currentData = accumulatedData
        if let data { currentData.append(data) }

        // *** NEW: enforce body size limit ***
        if currentData.count > self.maxRequestBodyBytes {
            self.sendErrorResponse(status: 413, message: "Request body too large (max 1MB)", connection: connection)
            return
        }

        // ... rest of existing logic unchanged ...
    }
}
```

### Step 3: Run tests

```bash
swift test --filter "LocalhostBridgeTests" 2>&1
```

### Step 4: Commit

```bash
git add Sources/DownloadKit/Network/LocalhostBridge.swift \
        Tests/DownloadKitTests/LocalhostBridgeTests.swift
git commit -m "fix(bridge): 1MB request body cap, dynamic version from Bundle

- readRequest returns 413 if accumulated data exceeds 1MB before header end
- LocalhostBridge(version:) injects the version string; defaults to
  Bundle CFBundleShortVersionString so /status never drifts from the app version"
```

---

## Task 6 — SpeedTracker + DownloadURLSession tuning

**Files:**
- Modify: `Sources/DownloadKit/Engine/DownloadEngine.swift` (SpeedTracker)
- Modify: `Sources/DownloadKit/Network/ChunkDownloader.swift` (URLSession config)
- Modify: `Tests/DownloadKitTests/DownloadEngineTests.swift`

### Context

Finding 1.4: `SpeedTracker.window` can grow to thousands of entries between prunes.  
Finding 4.3: `httpMaximumConnectionsPerHost = 32` is too aggressive; CDNs respond with 429, triggering unnecessary fallback overhead.

### Step 1: Write failing test for SpeedTracker cap

```swift
@Test("SpeedTracker caps window to 500 entries")
func testSpeedTracker_windowCap() {
    var tracker = SpeedTracker()
    // Record 1000 small bytes events
    for _ in 0..<1000 {
        tracker.record(bytes: 1)
    }
    // After prune during currentSpeed(), window should not exceed 500
    _ = tracker.currentSpeed()
    #expect(tracker.windowCount <= 500)
}
```

This requires exposing `windowCount` as a testable property (add `var windowCount: Int { window.count }` marked `internal`).

### Step 2: Implement SpeedTracker cap

In `SpeedTracker.record(bytes:)`, add a tail-drop cap after pruning:

```swift
public mutating func record(bytes: Int64) {
    guard bytes > 0 else { return }
    let now = clock.now
    window.append((time: now, bytes: bytes))
    prune(now: now)
    // Cap to prevent unbounded growth on high-frequency progress events
    if window.count > 500 {
        window.removeFirst(window.count - 500)
    }
}
```

### Step 3: Lower default connections per host

In `ChunkDownloader.swift`, change:

```swift
// BEFORE:
config.httpMaximumConnectionsPerHost = 32

// AFTER: Match the max chunk setting (8). Aggressive enough for performance,
// conservative enough to avoid CDN 429s.
config.httpMaximumConnectionsPerHost = 8
```

No new test needed — this is a configuration constant. The existing `ChunkDownloaderTests` provide regression coverage.

### Step 4: Run tests

```bash
swift test --filter "DownloadEngineTests/testSpeedTracker" 2>&1
```

### Step 5: Commit

```bash
git add Sources/DownloadKit/Engine/DownloadEngine.swift \
        Sources/DownloadKit/Network/ChunkDownloader.swift \
        Tests/DownloadKitTests/DownloadEngineTests.swift
git commit -m "perf(engine): cap SpeedTracker window at 500 entries, reduce connections/host to 8

- SpeedTracker.record now drops oldest entries when window exceeds 500
- httpMaximumConnectionsPerHost reduced from 32 to 8 to avoid CDN 429s"
```

---

## Task 7 — AppState: Telemetry caching + render debounce

**Files:**
- Modify: `Sources/HyperFetchApp/App/AppState.swift`

### Context

Finding 6.3: `totalDownloadedTodayBytes` recalculates via `reduce` on every access, allocating `Calendar.current` each time.  
Finding 6.4: `activeSocketCount` does a `reduce` and `allocatedMemoryMB` calls `task_info` (a Mach kernel trap) on every render frame.

The existing `speedSamplerTask` already runs at 1 Hz — the fix is to move these expensive computations into that timer and cache the results.

### Step 1: Implement in `AppState.swift`

**1a. Add cached backing stores:**

```swift
// Add these stored properties alongside speedHistory:
@Published private(set) var cachedActiveSocketCount: Int = 0
@Published private(set) var cachedAllocatedMemoryMB: Int = 48
@Published private(set) var cachedTotalDownloadedTodayBytes: Int64 = 0
```

**1b. Update the computed properties to return cached values:**

```swift
public var activeSocketCount: Int { cachedActiveSocketCount }
public var allocatedMemoryMB: Int { cachedAllocatedMemoryMB }
public var totalDownloadedTodayBytes: Int64 { cachedTotalDownloadedTodayBytes }
```

**1c. Move computation into `speedSamplerTask`:**

```swift
speedSamplerTask = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard let self else { return }

        let current = self.totalDownloadSpeed
        self.speedHistory.removeFirst()
        self.speedHistory.append(current)

        // Expensive telemetry — update at 1 Hz, not every render frame
        self.cachedActiveSocketCount = self.computeActiveSocketCount()
        self.cachedAllocatedMemoryMB = self.computeAllocatedMemoryMB()
        self.cachedTotalDownloadedTodayBytes = self.computeTotalDownloadedTodayBytes()
    }
}
```

**1d. Rename the original implementations** to `compute*` private methods (move logic there, unchanged):

```swift
private func computeActiveSocketCount() -> Int {
    // ... existing activeSocketCount body ...
}
private func computeAllocatedMemoryMB() -> Int {
    // ... existing allocatedMemoryMB body ...
}
private func computeTotalDownloadedTodayBytes() -> Int64 {
    let calendar = Calendar.current
    return tasks.reduce(0) { sum, task in
        // ... existing body ...
    }
}
```

> **Note:** This is a pure refactor — same logic, different call site. No new behaviour changes. The `@Published private(set)` properties ensure SwiftUI re-renders at the right time.

### Step 2: Run the app and confirm the status bar still updates

This is a UI change — no unit test possible for the visual output. Manually verify the status bar still updates while a download is active.

```bash
# Build only — confirm no compile errors
swift build --target HyperFetchApp 2>&1 | grep -E "error:|warning:" | head -20
```

### Step 3: Commit

```bash
git add Sources/HyperFetchApp/App/AppState.swift
git commit -m "perf(ui): cache telemetry at 1Hz instead of every render frame

- activeSocketCount, allocatedMemoryMB, totalDownloadedTodayBytes are now
  updated by the existing speedSamplerTask at 1 Hz and cached as @Published
  stored properties — eliminates reduce/mach-trap overhead from render path"
```

---

## Task 8 — Chrome Extension: processedDownloadIds cleanup race + cookie domain scope

**Files:**
- Modify: `extensions/chrome/background.js`

### Context

Finding 7.1: If the async IIFE throws before `cancelBrowserDownload` runs, the download ID stays in `processedDownloadIds` permanently, blocking retries.  
Finding 7.2: `getMergedCookies` merges cookies from up to 3 different domains (targetUrl, rawUrl, referrer) into one header — session tokens from the referrer domain leak onto requests to targetUrl's domain.

### Step 1: Fix `processedDownloadIds` cleanup

The fix is to schedule the timeout cleanup **immediately after** `processedDownloadIds.add`, before the async work, so it fires regardless of success/failure:

```js
// BEFORE:
processedDownloadIds.add(downloadItem.id);

(async () => {
  try {
    // ...
    if (success) {
      safeSuggest();
      cancelBrowserDownload(downloadItem.id);
    } else {
      // ...
      setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);
    }
  } catch (err) {
    // ...
    setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);
  }
})();

// AFTER:
processedDownloadIds.add(downloadItem.id);
// Guarantee cleanup regardless of outcome — if cancelBrowserDownload
// runs successfully, clearing the ID after 10s is harmless
setTimeout(() => processedDownloadIds.delete(downloadItem.id), 10000);

(async () => {
  try {
    // ... all existing logic unchanged ...
    // Remove the duplicate setTimeout calls inside catch/else blocks
  } catch (err) {
    console.error('[HyperFetch] Error during async interception:', err);
    safeSuggest({ filename: filename || fallbackName });
    // No need for setTimeout here anymore — already scheduled above
  }
})();
```

Remove the now-redundant `setTimeout(...delete...)` calls inside the `else` and `catch` blocks.

### Step 2: Fix cookie domain scoping in `getMergedCookies`

Replace the multi-URL merge with a single-domain fetch:

```js
// BEFORE: merges cookies from targetUrl, rawUrl, AND referrer
async function getMergedCookies(url1, url2, referrer) {
  const cookieMap = new Map();
  const urls = [];
  if (url1) urls.push(url1);
  if (url2 && !urls.includes(url2)) urls.push(url2);
  if (referrer && !urls.includes(referrer)) urls.push(referrer);
  // ...
}

// AFTER: only fetch cookies for the actual download target domain
async function getMergedCookies(targetUrl) {
  return getCookiesForUrl(targetUrl);
}
```

Update the call site in the async IIFE:

```js
// BEFORE:
const cookieString = await getMergedCookies(targetUrl, rawUrl, downloadItem.referrer);

// AFTER:
const cookieString = await getMergedCookies(targetUrl);
```

### Step 3: Verify extension still works

Load the extension in Chrome (unpacked from `extensions/chrome/`), trigger a download from a site that requires cookies, and confirm it still intercepts and forwards correctly.

### Step 4: Commit

```bash
git add extensions/chrome/background.js
git commit -m "fix(extension): guarantee processedDownloadIds cleanup, scope cookies to target domain

- setTimeout(delete, 10000) is now scheduled immediately after .add() so
  IDs are always cleaned up, even if the async IIFE throws early
- getMergedCookies now only fetches cookies for targetUrl — prevents
  session token leakage from referrer/rawUrl domains to the download host"
```

---

## Completion Checklist

After all 8 tasks:

```bash
cd /opt/homebrew/var/www/FDM
swift test 2>&1 | tail -5
# Expected: "Test run with N tests passed."
```

Review findings left intentionally out of scope (no-code or separate discussions):
- **Finding 1.2** (chunk resume with empty chunks after corruption) — requires schema migration logic; deferred.
- **Finding 1.5** (weak actor capture) — actor lifecycle guarantees make this safe in practice; noted in code comment.
- **Finding 3.2** (synchronous disk I/O inside actor) — debounce in Task 2 reduces call frequency enough that this is no longer hot; full async refactor is a larger rewrite deferred.
- **Finding 6.1** (AppState monolith split) — architectural change; deferred to a separate refactor session.
- **Finding 6.2** (filteredTasks over-invalidation) — the 1 Hz telemetry cache (Task 7) reduces this significantly; full debounce of task array updates is a separate task.
- **Capability gaps** (history, scheduling, duplicate detection, ETag storage) — new features; separate planning required.
- **Tauri dead code cleanup** — `desktop/` deletion is a separate PR after confirming no CI/CD references.
