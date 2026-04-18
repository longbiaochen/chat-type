import Foundation

enum RuntimePreflightIssue: Equatable, Sendable {
    case missingDesktopHost
    case hostLoginRequired
    case hostTokenUnavailable
    case hostBridgeUnavailable
    case missingTranscriptionAuthToken(String)

    var message: String {
        switch self {
        case .missingDesktopHost:
            return "Install Codex desktop on this Mac and sign in with ChatGPT before recording."
        case .hostLoginRequired:
            return "Open Codex on this Mac and make sure it is signed in with your ChatGPT account."
        case .hostTokenUnavailable:
            return "Codex is installed, but ChatType could not read a usable ChatGPT session token yet."
        case .hostBridgeUnavailable:
            return "ChatType could not verify the local Codex desktop login state right now. Relaunch Codex and try again."
        case .missingTranscriptionAuthToken(let envName):
            return "Set environment variable \(envName) before recording."
        }
    }
}

enum RuntimePreflight {
    static func issues(
        for config: AppConfig,
        environment: [String: String],
        authStatusProvider: (() throws -> AuthStatus)? = nil
    ) -> [RuntimePreflightIssue] {
        var issues: [RuntimePreflightIssue] = []
        let provider = authStatusProvider ?? defaultAuthStatusProvider

        if config.transcription.provider == .codexChatGPTBridge {
            appendDesktopHostIssues(into: &issues, authStatusProvider: provider)
        } else if config.transcription.provider == .openAICompatible {
            let envName = normalizedEnvName(config.transcription.openAIAuthTokenEnv)
            let token = environment[envName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if token.isEmpty {
                issues.append(.missingTranscriptionAuthToken(envName))
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

    private static func appendDesktopHostIssues(
        into issues: inout [RuntimePreflightIssue],
        authStatusProvider: () throws -> AuthStatus
    ) {
        for issue in desktopHostIssues(authStatusProvider: authStatusProvider) where !issues.contains(issue) {
            issues.append(issue)
        }
    }

    private static func desktopHostIssues(
        authStatusProvider: () throws -> AuthStatus
    ) -> [RuntimePreflightIssue] {
        do {
            let status = try authStatusProvider()
            let token = status.authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if token.isEmpty {
                return [.hostTokenUnavailable]
            }
            return []
        } catch let error as CodexAuthError {
            switch error {
            case .launcherNotFound:
                return [.missingDesktopHost]
            case .notChatGPT:
                return [.hostLoginRequired]
            case .missingToken:
                return [.hostTokenUnavailable]
            case .initializeFailed, .authFailed, .timedOut, .malformedResponse:
                return [.hostBridgeUnavailable]
            }
        } catch {
            return [.hostBridgeUnavailable]
        }
    }

    private static func defaultAuthStatusProvider() throws -> AuthStatus {
        try CodexAuthClient().fetchBestAvailableAuthStatus(includeToken: true)
    }
}
