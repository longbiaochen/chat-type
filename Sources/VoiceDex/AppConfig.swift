import Foundation

struct AppConfig: Codable, Sendable {
    var transcription: TranscriptionConfig = .init()
    var injection: InjectionConfig = .init()

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcription = try container.decodeIfPresent(TranscriptionConfig.self, forKey: .transcription) ?? .init()
        injection = try container.decodeIfPresent(InjectionConfig.self, forKey: .injection) ?? .init()
    }
}

enum TranscriptionProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case codexChatGPTBridge
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codexChatGPTBridge:
            return "ChatGPT Desktop Login"
        case .openAICompatible:
            return "OpenAI-Compatible Recovery"
        }
    }

    var caption: String {
        switch self {
        case .codexChatGPTBridge:
            return "Recommended. Uses your signed-in local Codex desktop session. No API key required."
        case .openAICompatible:
            return "Advanced recovery route. Bring your own OpenAI-compatible API only if the desktop login path is unavailable."
        }
    }
}

struct TranscriptionConfig: Codable, Sendable {
    var provider: TranscriptionProvider = .codexChatGPTBridge
    var hotkeyKeyCode: UInt32 = 96
    var chatGPTURL: String = "https://chatgpt.com/backend-api/transcribe"
    var openAITranscriptionURL: String = "https://api.openai.com/v1/audio/transcriptions"
    var openAIModel: String = "gpt-4o-mini-transcribe"
    var openAIAuthTokenEnv: String = "OPENAI_API_KEY"
    var sampleRateHz: Int = 24_000
    var maxDurationSeconds: Int = 120
    var hintTerms: [String] = []

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(TranscriptionProvider.self, forKey: .provider) ?? .codexChatGPTBridge
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? 96
        chatGPTURL = try container.decodeIfPresent(String.self, forKey: .chatGPTURL) ?? "https://chatgpt.com/backend-api/transcribe"
        openAITranscriptionURL = try container.decodeIfPresent(String.self, forKey: .openAITranscriptionURL) ?? "https://api.openai.com/v1/audio/transcriptions"
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? "gpt-4o-mini-transcribe"
        openAIAuthTokenEnv = try container.decodeIfPresent(String.self, forKey: .openAIAuthTokenEnv) ?? "OPENAI_API_KEY"
        sampleRateHz = try container.decodeIfPresent(Int.self, forKey: .sampleRateHz) ?? 24_000
        maxDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .maxDurationSeconds) ?? 120
        hintTerms = try container.decodeIfPresent([String].self, forKey: .hintTerms) ?? []
    }
}

struct InjectionConfig: Codable, Sendable {
    var preserveClipboard: Bool = true
    var restoreDelayMilliseconds: UInt64 = 350

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preserveClipboard = try container.decodeIfPresent(Bool.self, forKey: .preserveClipboard) ?? true
        restoreDelayMilliseconds = try container.decodeIfPresent(UInt64.self, forKey: .restoreDelayMilliseconds) ?? 350
    }
}

enum ConfigError: LocalizedError {
    case invalidPromptOutput

    var errorDescription: String? {
        switch self {
        case .invalidPromptOutput:
            return "转写提示词返回了空文本。"
        }
    }
}

struct ConfigStore {
    let fileManager: FileManager = .default

    var directoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ChatType", isDirectory: true)
    }

    var legacyDirectoryURLs: [URL] {
        [
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/VoiceDex", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/HotkeyVoice", isDirectory: true),
        ]
    }

    var legacyConfigURLs: [URL] {
        legacyDirectoryURLs.map { $0.appendingPathComponent("config.json") }
    }

    var configURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }

    func load() throws -> AppConfig {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: configURL.path),
           let legacyConfigURL = legacyConfigURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            try fileManager.copyItem(at: legacyConfigURL, to: configURL)
        }

        guard fileManager.fileExists(atPath: configURL.path) else {
            let config = AppConfig()
            try save(config)
            return config
        }

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        try save(config)
        return config
    }

    func save(_ config: AppConfig) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: [.atomic])
    }
}
