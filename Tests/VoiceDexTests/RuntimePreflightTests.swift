import Foundation
import Testing
@testable import VoiceDex

@Test
func preflightRequiresOpenAIKeyForPublicLaunchDefaults() {
    let issues = RuntimePreflight.issues(for: AppConfig(), environment: [:])

    #expect(
        issues == [
            .missingTranscriptionAuthToken("OPENAI_API_KEY"),
            .missingCleanupAuthToken("OPENAI_API_KEY"),
        ]
    )
}

@Test
func preflightRequiresCleanupEndpointAndModelWhenCleanupEnabled() {
    var config = AppConfig()
    config.cleanup.endpoint = ""
    config.cleanup.model = ""

    let issues = RuntimePreflight.issues(
        for: config,
        environment: ["OPENAI_API_KEY": "test-key"]
    )

    #expect(
        issues == [
            .missingCleanupEndpoint,
            .missingCleanupModel,
        ]
    )
}
