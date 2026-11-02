//
//  RateLimiter.swift
//  DownloadKit
//

import Foundation

/// Protocol defining operations for bandwidth rate limiting and token consumption.
public protocol RateLimiting: Sendable {
    func requestTokens(count: Int64) async throws
    func updateLimit(bytesPerSecond: Int64) async
    var bytesPerSecond: Int64 { get async }
}

/// Actor implementing the Token Bucket algorithm for precise bandwidth throttling and cooperative task cancellation.
public actor TokenBucketRateLimiter: RateLimiting {
    public private(set) var bytesPerSecond: Int64
    private var availableTokens: Double
    private var lastRefillTime: ContinuousClock.Instant
    private let clock: ContinuousClock

    public init(bytesPerSecond: Int64 = 0, initialTokens: Int64? = nil) {
        self.bytesPerSecond = bytesPerSecond
        self.clock = ContinuousClock()
        self.lastRefillTime = clock.now
        if let initial = initialTokens {
            self.availableTokens = Double(max(0, initial))
        } else {
            self.availableTokens = Double(max(0, bytesPerSecond))
        }
    }

    /// Dynamically updates the bandwidth limit in bytes per second.
    public func updateLimit(bytesPerSecond: Int64) {
        refill(targetCount: bytesPerSecond)
        let oldLimit = self.bytesPerSecond
        self.bytesPerSecond = bytesPerSecond
        self.lastRefillTime = clock.now
        if oldLimit <= 0 && bytesPerSecond > 0 {
            self.availableTokens = Double(bytesPerSecond)
        } else if bytesPerSecond > 0 {
            let maxCapacity = Double(bytesPerSecond)
            if self.availableTokens > maxCapacity {
                self.availableTokens = maxCapacity
            }
        }
    }

    /// Requests a specified number of byte tokens, sleeping cooperatively if rate limited.
    public func requestTokens(count: Int64) async throws {
        guard count > 0 else { return }
        try Task.checkCancellation()

        // If bytesPerSecond <= 0, no throttling (instant return)
        guard bytesPerSecond > 0 else { return }

        refill(targetCount: count)

        while availableTokens < Double(count) {
            try Task.checkCancellation()
            guard bytesPerSecond > 0 else { return }

            refill(targetCount: count)
            if availableTokens >= Double(count) {
                break
            }

            let deficit = Double(count) - availableTokens
            let secondsToWait = deficit / Double(bytesPerSecond)
            let totalNanos = UInt64(max(1.0, secondsToWait * 1_000_000_000))
            let sleepNanos = min(max(1_000_000, totalNanos), 50_000_000) // 1ms - 50ms slices for responsive cancellation & updates

            try await Task.sleep(nanoseconds: sleepNanos)
            refill(targetCount: count)
        }

        availableTokens -= Double(count)
    }

    private func refill(targetCount: Int64) {
        let now = clock.now
        let elapsed = lastRefillTime.duration(to: now)
        let (seconds, attoseconds) = elapsed.components
        let elapsedSeconds = Double(seconds) + Double(attoseconds) * 1e-18

        if elapsedSeconds > 0 && bytesPerSecond > 0 {
            let addedTokens = elapsedSeconds * Double(bytesPerSecond)
            let maxCapacity = Double(max(bytesPerSecond, targetCount))
            availableTokens = min(max(availableTokens, maxCapacity), availableTokens + addedTokens)
            lastRefillTime = now
        } else if bytesPerSecond <= 0 {
            lastRefillTime = now
        }
    }
}
