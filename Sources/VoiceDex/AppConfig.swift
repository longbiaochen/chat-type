import Foundation

struct AppConfig: Codable, Sendable {
    var transcription: TranscriptionConfig = .init()
    var cleanup: CleanupConfig = .init()
    var injection: InjectionConfig = .init()

    static let defaultCleanupPrompt = """
    只做轻量润色：修正标点、大小写、空格和明显语病；保持原意、语气和结构；保持中英混合原样；不要翻译；不要删减信息；不要改动代码、命令、文件路径、URL、邮箱、版本号、参数名、产品名。
    """

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcription = try container.decodeIfPresent(TranscriptionConfig.self, forKey: .transcription) ?? .init()
        cleanup = try container.decodeIfPresent(CleanupConfig.self, forKey: .cleanup) ?? .init()
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
            return "Codex Bridge"
        case .openAICompatible:
            return "OpenAI-Compatible"
        }
    }

    var caption: String {
        switch self {
        case .codexChatGPTBridge:
            return "Experimental. Uses local Codex login state and is not the recommended public launch path."
        case .openAICompatible:
            return "Recommended. Stable OpenAI-compatible transcription with your own API key."
        }
    }
}

struct TranscriptionConfig: Codable, Sendable {
    var provider: TranscriptionProvider = .openAICompatible
    var hotkeyKeyCode: UInt32 = 96
    var chatGPTURL: String = "https://chatgpt.com/backend-api/transcribe"
    var openAITranscriptionURL: String = "https://api.openai.com/v1/audio/transcriptions"
    var openAIModel: String = "gpt-4o-mini-transcribe"
    var openAIAuthTokenEnv: String = "OPENAI_API_KEY"
    var sampleRateHz: Int = 24_000
    var maxDurationSeconds: Int = 120

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
    }
}

struct CleanupConfig: Codable, Sendable {
    var enabled: Bool = true
    var endpoint: String = "https://api.openai.com/v1/chat/completions"
    var model: String = "gpt-4.1-mini"
    var systemPrompt: String = AppConfig.defaultCleanupPrompt
    var authTokenEnv: String = "OPENAI_API_KEY"
    var authHeaderPrefix: String = "Bearer"

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? AppConfig.defaultCleanupPrompt
        authTokenEnv = try container.decodeIfPresent(String.self, forKey: .authTokenEnv) ?? "OPENAI_API_KEY"
        authHeaderPrefix = try container.decodeIfPresent(String.self, forKey: .authHeaderPrefix) ?? "Bearer"
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
    case missingEndpoint
    case missingModel

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Cleanup 已启用，但没有配置 cleanup.endpoint。"
        case .missingModel:
            return "Cleanup 已启用，但没有配置 cleanup.model。"
        }
    }
}

struct ConfigStore {
    let fileManager: FileManager = .default

    var directoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceDex", isDirectory: true)
    }

    var legacyDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/HotkeyVoice", isDirectory: true)
    }

    var configURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }

    var legacyConfigURL: URL {
        legacyDirectoryURL.appendingPathComponent("config.json")
    }

    func load() throws -> AppConfig {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: configURL.path),
           fileManager.fileExists(atPath: legacyConfigURL.path) {
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
