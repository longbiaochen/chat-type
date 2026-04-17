import Foundation

enum RuntimePreflightIssue: Equatable, Sendable {
    case missingTranscriptionAuthToken(String)
    case missingCleanupEndpoint
    case missingCleanupModel
    case missingCleanupAuthToken(String)

    var message: String {
        switch self {
        case .missingTranscriptionAuthToken(let envName):
            return "Set environment variable \(envName) before recording."
        case .missingCleanupEndpoint:
            return "Cleanup is enabled, but the cleanup endpoint is empty."
        case .missingCleanupModel:
            return "Cleanup is enabled, but the cleanup model is empty."
        case .missingCleanupAuthToken(let envName):
            return "Cleanup is enabled, but environment variable \(envName) is missing."
        }
    }
}

enum RuntimePreflight {
    static func issues(for config: AppConfig, environment: [String: String]) -> [RuntimePreflightIssue] {
        var issues: [RuntimePreflightIssue] = []

        if config.transcription.provider == .openAICompatible {
            let envName = normalizedEnvName(config.transcription.openAIAuthTokenEnv)
            let token = environment[envName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if token.isEmpty {
                issues.append(.missingTranscriptionAuthToken(envName))
            }
        }

        if config.cleanup.enabled {
            if config.cleanup.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.missingCleanupEndpoint)
            }
            if config.cleanup.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.missingCleanupModel)
            }

            let envName = normalizedEnvName(config.cleanup.authTokenEnv)
            let token = environment[envName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if token.isEmpty {
                issues.append(.missingCleanupAuthToken(envName))
            }
        }

        return issues
    }

    static func summary(for issues: [RuntimePreflightIssue]) -> String? {
        guard let firstIssue = issues.first else {
            return nil
        }

        if issues.count == 1 {
            return firstIssue.message
        }

        return "\(firstIssue.message) \(issues.count - 1) more setting issue(s) need attention."
    }

    private static func normalizedEnvName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "OPENAI_API_KEY" : trimmed
    }
}
