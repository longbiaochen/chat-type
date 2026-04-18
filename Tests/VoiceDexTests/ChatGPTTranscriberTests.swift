import Foundation
import Testing
@testable import ChatType

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requestBodies: [String] = []

    func append(_ body: String) {
        lock.lock()
        requestBodies.append(body)
        lock.unlock()
    }

    func bodies() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requestBodies
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private func makeAudioFixture(named name: String = UUID().uuidString) throws -> RecordedAudio {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wav")
    try Data("fake-audio".utf8).write(to: url)
    return RecordedAudio(fileURL: url, durationMs: 1_000)
}

@Test
func openAICompatibleRouteIncludesPromptField() async throws {
    var config = AppConfig().transcription
    config.provider = .openAICompatible
    config.hintTerms = ["budget v2.xlsx", "ChatType"]

    let capture = RequestCapture()
    let transcriber = ChatGPTTranscriber(
        authClient: CodexAuthClient(),
        config: config,
        dataLoader: { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            capture.append(body)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"ChatType budget v2.xlsx"}"#.utf8), response)
        }
    )

    let originalEnvironment = ProcessInfo.processInfo.environment
    setenv(config.openAIAuthTokenEnv, "test-key", 1)
    defer {
        if let existing = originalEnvironment[config.openAIAuthTokenEnv] {
            setenv(config.openAIAuthTokenEnv, existing, 1)
        } else {
            unsetenv(config.openAIAuthTokenEnv)
        }
    }

    let audio = try makeAudioFixture()
    let result = try await transcriber.transcribe(audio)

    #expect(result.metrics.promptIncluded == true)
    #expect(capture.bodies().count == 1)
    #expect(capture.bodies()[0].contains("name=\"prompt\""))
    #expect(capture.bodies()[0].contains("budget v2.xlsx"))
}

@Test
func codexBridgeFallsBackWhenPromptFieldIsRejected() async throws {
    var config = AppConfig().transcription
    config.provider = .codexChatGPTBridge
    config.hintTerms = ["ChatType"]

    let capture = RequestCapture()
    let capability = BridgePromptCapabilityStore()
    let authClient = CodexAuthClient(
        cache: AuthStatusCache(ttl: 600),
        liveFetch: { _, _ in
            AuthStatus(authMethod: "chatgpt", authToken: "desktop-token")
        }
    )

    let attempts = AttemptCounter()
    let transcriber = ChatGPTTranscriber(
        authClient: authClient,
        config: config,
        bridgePromptCapability: capability,
        dataLoader: { request in
            let attempt = attempts.next()
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            capture.append(body)

            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(#"{"message":"prompt unsupported"}"#.utf8), response)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(#"{"text":"ChatType done"}"#.utf8), response)
        }
    )

    let audio = try makeAudioFixture()
    let result = try await transcriber.transcribe(audio)

    #expect(result.text == "ChatType done")
    #expect(result.metrics.promptIncluded == false)
    #expect(capture.bodies().count == 2)
    #expect(capture.bodies()[0].contains("name=\"prompt\""))
    #expect(capture.bodies()[1].contains("name=\"prompt\"") == false)
}
