import Foundation
import Testing
@testable import ChatType

private final class FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Test
func authStatusCacheReturnsWarmTokenWithoutRefreshingAgain() throws {
    let cache = AuthStatusCache(ttl: 600, now: { Date(timeIntervalSince1970: 1_000) })
    cache.store(AuthStatus(authMethod: "chatgpt", authToken: "warm-token"))

    let counter = FetchCounter()
    let client = CodexAuthClient(
        cache: cache,
        now: { Date(timeIntervalSince1970: 1_100) },
        liveFetch: { _, _ in
            counter.increment()
            return AuthStatus(authMethod: "chatgpt", authToken: "live-token")
        }
    )

    let status = try client.fetchBestAvailableAuthStatus(includeToken: true)
    #expect(status.authToken == "warm-token")
    #expect(counter.count() == 0)
}

@Test
func authStatusCacheExpiresAndFallsBackToLiveFetch() throws {
    let cache = AuthStatusCache(ttl: 60, now: { Date(timeIntervalSince1970: 1_000) })
    cache.store(AuthStatus(authMethod: "chatgpt", authToken: "stale-token"))

    let counter = FetchCounter()
    let client = CodexAuthClient(
        cache: cache,
        now: { Date(timeIntervalSince1970: 1_200) },
        liveFetch: { _, refreshToken in
            counter.increment()
            #expect(refreshToken == false)
            return AuthStatus(authMethod: "chatgpt", authToken: "fresh-token")
        }
    )

    let status = try client.fetchBestAvailableAuthStatus(includeToken: true)
    #expect(status.authToken == "fresh-token")
    #expect(counter.count() == 1)
}
