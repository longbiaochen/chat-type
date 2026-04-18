import Foundation
import Testing
@testable import ChatType

@Test
func defaultConfigUsesChatTypeDesktopLoginDefaults() throws {
    let config = AppConfig()
    #expect(config.transcription.hotkeyKeyCode == 96)
    #expect(config.transcription.provider == .codexChatGPTBridge)
    #expect(config.transcription.openAITranscriptionURL == "https://api.openai.com/v1/audio/transcriptions")
    #expect(config.transcription.openAIModel == "gpt-4o-mini-transcribe")
    #expect(config.transcription.openAIAuthTokenEnv == "OPENAI_API_KEY")
    #expect(config.transcription.hintTerms.isEmpty)
    #expect(config.transcription.chatGPTURL == "https://chatgpt.com/backend-api/transcribe")
}

@Test
func configRoundTripPreservesHiddenHintTerms() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var config = AppConfig()
    config.transcription.hintTerms = [
        "budget v2.xlsx",
        "ChatType",
        "review",
    ]

    let configURL = directory.appendingPathComponent("config.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: configURL)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
    #expect(decoded.transcription.hintTerms == [
        "budget v2.xlsx",
        "ChatType",
        "review",
    ])
}

@Test
func legacyCleanupConfigStillDecodesWithoutCrash() throws {
    let json = """
    {
      "cleanup": {
        "enabled": true,
        "endpoint": "https://example.com/v1/chat/completions",
        "model": "legacy-cleanup-model",
        "systemPrompt": "Legacy prompt",
        "authTokenEnv": "LEGACY_KEY",
        "authHeaderPrefix": "Bearer"
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    #expect(decoded.transcription.provider == .codexChatGPTBridge)
    #expect(decoded.transcription.hintTerms.isEmpty)
}
