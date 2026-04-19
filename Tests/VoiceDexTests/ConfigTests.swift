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
func defaultConfigEncodesTerminologyDefaults() throws {
    let data = try JSONEncoder().encode(AppConfig())
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let transcription = try #require(object["transcription"] as? [String: Any])
    let terminology = try #require(transcription["terminology"] as? [String: Any])

    #expect(terminology["enabled"] as? Bool == true)
    #expect((terminology["importedEntries"] as? [Any])?.isEmpty == true)
    #expect(terminology["lastImportedSource"] == nil)
    #expect(terminology["lastImportedAt"] == nil)
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
func configRoundTripPreservesImportedTerminologyEntries() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var config = AppConfig()
    config.transcription.terminology.importedEntries = [
        TerminologyEntry(
            canonical: "TypeWhisper",
            aliases: ["Type Whisper", "Takwiisper"],
            caseSensitive: true
        ),
        TerminologyEntry(
            canonical: "OpenAI Compatible",
            aliases: ["Open AI Compatible"],
            caseSensitive: true
        ),
    ]
    config.transcription.terminology.lastImportedSource = "/Users/test/Library/Application Support/TypeWhisper/dictionary.store"
    config.transcription.terminology.lastImportedAt = "2026-04-19T10:00:00Z"

    let configURL = directory.appendingPathComponent("config.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: configURL)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
    #expect(decoded.transcription.terminology.enabled == true)
    #expect(decoded.transcription.terminology.importedEntries.count == 2)
    #expect(decoded.transcription.terminology.importedEntries[0].canonical == "TypeWhisper")
    #expect(decoded.transcription.terminology.importedEntries[0].aliases == ["Type Whisper", "Takwiisper"])
    #expect(decoded.transcription.terminology.lastImportedSource == "/Users/test/Library/Application Support/TypeWhisper/dictionary.store")
    #expect(decoded.transcription.terminology.lastImportedAt == "2026-04-19T10:00:00Z")
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

@Test
func legacyConfigWithoutTerminologyReencodesWithTerminologyDefaults() throws {
    let json = """
    {
      "transcription": {
        "hintTerms": ["ChatType"]
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
    let reencoded = try JSONEncoder().encode(decoded)
    let object = try #require(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
    let transcription = try #require(object["transcription"] as? [String: Any])
    let terminology = try #require(transcription["terminology"] as? [String: Any])

    #expect(terminology["enabled"] as? Bool == true)
    #expect((terminology["importedEntries"] as? [Any])?.isEmpty == true)
}
