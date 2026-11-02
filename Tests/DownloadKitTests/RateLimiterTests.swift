import Testing
import Foundation
@testable import DownloadKit

@Suite("RateLimiter Tests")
struct RateLimiterTests {

    @Test("Unlimited mode has no latency")
    func testUnlimitedMode() async throws {
        let limiter = TokenBucketRateLimiter(bytesPerSecond: 0)
        let speed = await limiter.bytesPerSecond
        #expect(speed == 0)

        let start = ContinuousClock.now
        try await limiter.requestTokens(count: 1_000_000)
        let elapsed = start.duration(to: ContinuousClock.now)
        #expect(elapsed < .milliseconds(50))

        // Negative limit should also be unlimited
        let negativeLimiter = TokenBucketRateLimiter(bytesPerSecond: -100)
        try await negativeLimiter.requestTokens(count: 500_000)
    }

    @Test("Initial burst consumption succeeds immediately then throttles deficit")
    func testTokenConsumptionAndWaitTime() async throws {
        // 50,000 B/s with 50,000 initial burst tokens
        let limiter = TokenBucketRateLimiter(bytesPerSecond: 50_000)

        // Burst consumption: first 50,000 bytes should be consumed immediately
        let burstStart = ContinuousClock.now
        try await limiter.requestTokens(count: 50_000)
        let burstElapsed = burstStart.duration(to: ContinuousClock.now)
        #expect(burstElapsed < .milliseconds(50))

        // Now bucket is depleted. Requesting 25,000 bytes should wait ~0.5s (25000 / 50000 = 0.5s)
        let throttleStart = ContinuousClock.now
        try await limiter.requestTokens(count: 25_000)
        let throttleElapsed = throttleStart.duration(to: ContinuousClock.now)
        #expect(throttleElapsed >= .milliseconds(400))
        #expect(throttleElapsed <= .milliseconds(800))
    }

    @Test("Dynamically updating limit unblocks or adjusts wait time")
    func testDynamicallyUpdatingLimit() async throws {
        // Start with very slow limit: 100 B/s with 0 initial tokens
        let limiter = TokenBucketRateLimiter(bytesPerSecond: 100, initialTokens: 0)

        // Requesting 1,000 bytes would normally take 10 seconds!
        // But we update the limit to 1,000,000 B/s shortly after starting
        let updateTask = Task {
            try await Task.sleep(nanoseconds: 40_000_000) // 40ms
            await limiter.updateLimit(bytesPerSecond: 1_000_000)
        }

        let start = ContinuousClock.now
        try await limiter.requestTokens(count: 1_000)
        let elapsed = start.duration(to: ContinuousClock.now)
        _ = await updateTask.result

        // Should complete well within 500ms instead of 10 seconds
        #expect(elapsed < .milliseconds(500))
        let newLimit = await limiter.bytesPerSecond
        #expect(newLimit == 1_000_000)
    }

    @Test("Dynamically removing limit unblocks waiting callers immediately")
    func testDynamicallyRemovingLimit() async throws {
        let limiter = TokenBucketRateLimiter(bytesPerSecond: 10, initialTokens: 0)

        let updateTask = Task {
            try await Task.sleep(nanoseconds: 40_000_000)
            await limiter.updateLimit(bytesPerSecond: 0) // Unlimited
        }

        let start = ContinuousClock.now
        try await limiter.requestTokens(count: 10_000)
        let elapsed = start.duration(to: ContinuousClock.now)
        _ = await updateTask.result

        #expect(elapsed < .milliseconds(500))
    }

    @Test("Cooperative cancellation while waiting throws CancellationError")
    func testCancellationWhileWaiting() async throws {
        let limiter = TokenBucketRateLimiter(bytesPerSecond: 100, initialTokens: 0)

        let waitTask = Task {
            try await limiter.requestTokens(count: 10_000)
        }

        try await Task.sleep(nanoseconds: 30_000_000) // 30ms
        waitTask.cancel()

        let result = await waitTask.result
        switch result {
        case .success:
            Issue.record("Expected CancellationError but succeeded")
        case .failure(let error):
            #expect(error is CancellationError)
        }
    }

    @Test("Zero or negative token requests are no-ops")
    func testZeroOrNegativeRequests() async throws {
        let limiter = TokenBucketRateLimiter(bytesPerSecond: 10_000, initialTokens: 0)
        let start = ContinuousClock.now
        try await limiter.requestTokens(count: 0)
        try await limiter.requestTokens(count: -100)
        let elapsed = start.duration(to: ContinuousClock.now)
        #expect(elapsed < .milliseconds(20))
    }
}
