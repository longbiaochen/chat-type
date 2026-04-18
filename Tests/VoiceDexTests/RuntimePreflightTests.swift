import Foundation
import Testing
@testable import ChatType

@Test
func preflightRequiresDesktopHostForChatTypeDefaults() {
    let issues = RuntimePreflight.issues(
        for: AppConfig(),
        environment: [:],
        authStatusProvider: {
            throw CodexAuthError.launcherNotFound
        }
    )

    #expect(issues == [.missingDesktopHost])
}

@Test
func preflightRequiresChatGPTLoginWhenCodexIsNotSignedInWithChatGPT() {
    let issues = RuntimePreflight.issues(
        for: AppConfig(),
        environment: [:],
        authStatusProvider: {
            throw CodexAuthError.notChatGPT
        }
    )

    #expect(issues == [.hostLoginRequired])
}

@Test
func preflightRequiresOpenAIKeyInRecoveryMode() {
    var config = AppConfig()
    config.transcription.provider = .openAICompatible

    let issues = RuntimePreflight.issues(for: config, environment: [:])

    #expect(issues == [.missingTranscriptionAuthToken("OPENAI_API_KEY")])
}

@Test
func legacyCleanupConfigDoesNotAddDesktopHostRequirementToRecoveryMode() {
    var config = AppConfig()
    config.transcription.provider = .openAICompatible

    let issues = RuntimePreflight.issues(
        for: config,
        environment: ["OPENAI_API_KEY": "test-key"],
        authStatusProvider: {
            throw CodexAuthError.launcherNotFound
        }
    )

    #expect(issues.isEmpty)
}
