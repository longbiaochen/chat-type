import Foundation

enum TranscriptionError: LocalizedError {
    case invalidAudio
    case payloadTooLarge
    case transcriptionFailed(String)
    case invalidResponse
    case missingAuthTokenEnv(String)

    var errorDescription: String? {
        switch self {
        case .invalidAudio:
            return "录音文件无效。"
        case .payloadTooLarge:
            return "录音文件超过 10 MB，当前实现不发送。"
        case .transcriptionFailed(let message):
            return "ChatGPT 转写失败：\(message)"
        case .invalidResponse:
            return "ChatGPT 转写返回了空文本。"
        case .missingAuthTokenEnv(let envName):
            return "缺少转写 API key，请设置环境变量 \(envName)。"
        }
    }
}

struct TranscriptionMetrics: Sendable, Equatable {
    let provider: TranscriptionProvider
    let audioDurationMs: Int
    let audioBytes: Int
    let authMs: Int
    let transcribeMs: Int
    let promptIncluded: Bool
}

struct TranscriptionResult: Sendable, Equatable {
    let text: String
    let metrics: TranscriptionMetrics
}

final class BridgePromptCapabilityStore: @unchecked Sendable {
    static let shared = BridgePromptCapabilityStore()

    private let lock = NSLock()
    private var supportsPrompt: Bool?

    func value() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return supportsPrompt
    }

    func mark(_ value: Bool) {
        lock.lock()
        supportsPrompt = value
        lock.unlock()
    }
}

struct ChatGPTTranscriber: Sendable {
    let authClient: CodexAuthClient
    let config: TranscriptionConfig
    let promptBuilder: TranscriptionPromptBuilder
    let bridgePromptCapability: BridgePromptCapabilityStore
    let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        authClient: CodexAuthClient,
        config: TranscriptionConfig,
        promptBuilder: TranscriptionPromptBuilder = .init(),
        bridgePromptCapability: BridgePromptCapabilityStore = .shared,
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.authClient = authClient
        self.config = config
        self.promptBuilder = promptBuilder
        self.bridgePromptCapability = bridgePromptCapability
        self.dataLoader = dataLoader
    }

    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult {
        let data = try Data(contentsOf: audio.fileURL)
        guard !data.isEmpty else {
            throw TranscriptionError.invalidAudio
        }
        guard data.count <= 10 * 1024 * 1024 else {
            throw TranscriptionError.payloadTooLarge
        }

        let prompt = promptBuilder.buildPrompt(hintTerms: config.hintTerms)

        switch config.provider {
        case .codexChatGPTBridge:
            let authStarted = DispatchTime.now().uptimeNanoseconds
            let authStatus = try authClient.fetchBestAvailableAuthStatus(includeToken: true)
            let authMs = elapsedMilliseconds(since: authStarted)
            guard let token = authStatus.authToken else {
                throw CodexAuthError.missingToken
            }
            let transcribeStarted = DispatchTime.now().uptimeNanoseconds
            let response = try await transcribeViaChatGPTBridge(
                audioData: data,
                token: token,
                prompt: prompt
            )
            let transcribeMs = elapsedMilliseconds(since: transcribeStarted)
            return TranscriptionResult(
                text: response.text,
                metrics: TranscriptionMetrics(
                    provider: .codexChatGPTBridge,
                    audioDurationMs: audio.durationMs,
                    audioBytes: data.count,
                    authMs: authMs,
                    transcribeMs: transcribeMs,
                    promptIncluded: response.promptIncluded
                )
            )
        case .openAICompatible:
            let transcribeStarted = DispatchTime.now().uptimeNanoseconds
            let text = try await transcribeViaOpenAICompatible(
                audioData: data,
                prompt: prompt
            )
            let transcribeMs = elapsedMilliseconds(since: transcribeStarted)
            return TranscriptionResult(
                text: text,
                metrics: TranscriptionMetrics(
                    provider: .openAICompatible,
                    audioDurationMs: audio.durationMs,
                    audioBytes: data.count,
                    authMs: 0,
                    transcribeMs: transcribeMs,
                    promptIncluded: true
                )
            )
        }
    }

    private func transcribeViaChatGPTBridge(
        audioData: Data,
        token: String,
        prompt: String
    ) async throws -> (text: String, promptIncluded: Bool) {
        let capability = bridgePromptCapability.value()
        if capability == false {
            let text = try await executeTranscriptionRequest(
                makeChatGPTBridgeRequest(
                    audioData: audioData,
                    token: token,
                    prompt: nil
                ),
                providerLabel: "ChatGPT"
            )
            return (text, false)
        }

        do {
            let text = try await executeTranscriptionRequest(
                makeChatGPTBridgeRequest(
                    audioData: audioData,
                    token: token,
                    prompt: prompt
                ),
                providerLabel: "ChatGPT"
            )
            bridgePromptCapability.mark(true)
            return (text, true)
        } catch {
            let fallbackText = try await executeTranscriptionRequest(
                makeChatGPTBridgeRequest(
                    audioData: audioData,
                    token: token,
                    prompt: nil
                ),
                providerLabel: "ChatGPT"
            )
            bridgePromptCapability.mark(false)
            return (fallbackText, false)
        }
    }

    private func makeChatGPTBridgeRequest(
        audioData: Data,
        token: String,
        prompt: String?
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: config.chatGPTURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(makeBoundary())", forHTTPHeaderField: "Content-Type")
        let boundary = request.value(forHTTPHeaderField: "Content-Type")!.split(separator: "=").last.map(String.init) ?? makeBoundary()
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            extraFields: prompt.map { ["prompt": $0] } ?? [:]
        )
        return request
    }

    private func transcribeViaOpenAICompatible(audioData: Data, prompt: String) async throws -> String {
        let token = ProcessInfo.processInfo.environment[config.openAIAuthTokenEnv] ?? ""
        guard !token.isEmpty else {
            throw TranscriptionError.missingAuthTokenEnv(config.openAIAuthTokenEnv)
        }

        let boundary = makeBoundary()
        var request = URLRequest(url: URL(string: config.openAITranscriptionURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            audioData: audioData,
            extraFields: [
                "model": config.openAIModel,
                "prompt": prompt,
            ]
        )

        return try await executeTranscriptionRequest(request, providerLabel: "OpenAI-compatible")
    }

    private func executeTranscriptionRequest(_ request: URLRequest, providerLabel: String) async throws -> String {
        let (responseData, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.transcriptionFailed("\(providerLabel) missing HTTP response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let providerMessage = decodeProviderMessage(from: responseData) ?? "status \(httpResponse.statusCode)"
            throw TranscriptionError.transcriptionFailed(providerMessage)
        }

        let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if let text = object?["text"] as? String, !text.isEmpty {
            return text
        }
        if let text = object?["transcript"] as? String, !text.isEmpty {
            return text
        }

        throw TranscriptionError.invalidResponse
    }

    private func makeBoundary() -> String {
        "ChatType-\(UUID().uuidString)"
    }

    private func makeMultipartBody(boundary: String, audioData: Data, extraFields: [String: String]) -> Data {
        var body = Data()
        for (name, value) in extraFields.sorted(by: { $0.key < $1.key }) {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
            body.append(contentsOf: "\(value)\r\n".utf8)
        }
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: audio/wav\r\n\r\n".utf8)
        body.append(audioData)
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)
        return body
    }

    private func decodeProviderMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}

extension ChatGPTTranscriber: Transcriber {}
