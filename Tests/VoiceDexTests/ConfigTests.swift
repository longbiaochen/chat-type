import Foundation
import Testing
@testable import VoiceDex

@Test
func defaultConfigUsesPublicLaunchDefaults() throws {
    let config = AppConfig()
    #expect(config.transcription.hotkeyKeyCode == 96)
    #expect(config.transcription.provider == .openAICompatible)
    #expect(config.transcription.openAITranscriptionURL == "https://api.openai.com/v1/audio/transcriptions")
    #expect(config.transcription.openAIModel == "gpt-4o-mini-transcribe")
    #expect(config.transcription.openAIAuthTokenEnv == "OPENAI_API_KEY")
    #expect(config.cleanup.enabled == true)
    #expect(config.cleanup.endpoint == "https://api.openai.com/v1/chat/completions")
    #expect(config.cleanup.model == "gpt-4.1-mini")
    #expect(config.cleanup.authTokenEnv == "OPENAI_API_KEY")
    #expect(config.transcription.chatGPTURL == "https://chatgpt.com/backend-api/transcribe")
}

@Test
func configRoundTripPreservesCustomCleanupPrompt() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var config = AppConfig()
    config.cleanup.enabled = true
    config.cleanup.endpoint = "https://example.com/v1/chat/completions"
    config.cleanup.model = "gpt-test"
    config.cleanup.systemPrompt = "Keep commands untouched."

    let configURL = directory.appendingPathComponent("config.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: configURL)

    let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
    #expect(decoded.cleanup.systemPrompt == "Keep commands untouched.")
    #expect(decoded.cleanup.model == "gpt-test")
}
