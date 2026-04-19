import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(
        config: AppConfig,
        onSave: @escaping (AppConfig) -> Void,
        onImportTypeWhisperTerminology: @escaping (AppConfig) -> Result<AppConfig, any Error>,
        onOpenConfigFolder: @escaping () -> Void
    ) {
        let view = PreferencesView(
            initialConfig: config,
            onSave: onSave,
            onImportTypeWhisperTerminology: onImportTypeWhisperTerminology,
            onOpenConfigFolder: onOpenConfigFolder
        )
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ChatType Settings"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        window.contentViewController = hostingController

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PreferencesView: View {
    @State private var config: AppConfig
    @State private var showsAdvancedRecovery: Bool
    @State private var accessibilityRefreshNonce: Int = 0
    @State private var terminologyImportMessage: String?
    @State private var terminologyImportIsError = false

    let onSave: (AppConfig) -> Void
    let onImportTypeWhisperTerminology: (AppConfig) -> Result<AppConfig, any Error>
    let onOpenConfigFolder: () -> Void

    init(
        initialConfig: AppConfig,
        onSave: @escaping (AppConfig) -> Void,
        onImportTypeWhisperTerminology: @escaping (AppConfig) -> Result<AppConfig, any Error>,
        onOpenConfigFolder: @escaping () -> Void
    ) {
        _config = State(initialValue: initialConfig)
        _showsAdvancedRecovery = State(initialValue: initialConfig.transcription.provider == .openAICompatible)
        _terminologyImportMessage = State(initialValue: Self.terminologyStatusMessage(for: initialConfig))
        self.onSave = onSave
        self.onImportTypeWhisperTerminology = onImportTypeWhisperTerminology
        self.onOpenConfigFolder = onOpenConfigFolder
    }

    private var runtimeIssues: [RuntimePreflightIssue] {
        RuntimePreflight.issues(
            for: config,
            environment: ProcessInfo.processInfo.environment
        )
    }

    private var hostStatus: SetupStatus {
        if config.transcription.provider == .openAICompatible {
            return SetupStatus(
                title: "Advanced recovery route selected",
                subtitle: "Desktop login checks are bypassed while you use your own compatible API."
            )
        }

        if let issue = runtimeIssues.first(where: {
            switch $0 {
            case .missingDesktopHost, .hostLoginRequired, .hostTokenUnavailable, .hostBridgeUnavailable:
                return true
            default:
                return false
            }
        }) {
            return SetupStatus(title: "Needs attention", subtitle: issue.message, isReady: false)
        }

        return SetupStatus(
            title: "Ready",
            subtitle: "Signed-in Codex desktop session detected. ChatType can use your local ChatGPT login state."
        )
    }

    private var microphoneStatus: SetupStatus {
        switch AudioRecorder.microphonePermissionState() {
        case .granted:
            return SetupStatus(title: "Granted", subtitle: "Microphone access is ready.")
        case .undetermined:
            return SetupStatus(title: "Not requested yet", subtitle: "Press F5 once and macOS will ask for microphone access.", isReady: false)
        case .denied:
            return SetupStatus(title: "Needs permission", subtitle: "Enable microphone access in System Settings > Privacy & Security.", isReady: false)
        }
    }

    private var accessibilityStatus: SetupStatus {
        _ = accessibilityRefreshNonce
        let guidance = AccessibilityPermission.repairGuidance()

        if AccessibilityPermission.isTrusted() {
            return SetupStatus(title: "Granted", subtitle: "Auto-paste is ready.")
        }

        return SetupStatus(
            title: "Optional but recommended",
            subtitle: guidance.subtitle,
            isReady: false
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ChatType")
                    .font(.system(size: 28, weight: .semibold))

                Text("Use your signed-in Codex desktop session to transcribe speech without API keys or local model setup. Press F5 to start recording, then press F5 again to finish.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                setupCard
                quickStartCard

                settingsCard(title: "Trigger") {
                    HStack {
                        Text("Hotkey")
                        Spacer()
                        Text("F5")
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard(title: "Transcription") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default route")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("ChatGPT Desktop Login")
                            .font(.system(size: 14, weight: .semibold))
                        Text("ChatType uses the local Codex desktop login state on this Mac. No API key is required in the normal flow.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup(
                        "Advanced recovery route",
                        isExpanded: Binding(
                            get: { showsAdvancedRecovery || config.transcription.provider == .openAICompatible },
                            set: { showsAdvancedRecovery = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Transcription Route", selection: $config.transcription.provider) {
                                Text("ChatGPT Desktop Login").tag(TranscriptionProvider.codexChatGPTBridge)
                                Text("OpenAI-Compatible Recovery").tag(TranscriptionProvider.openAICompatible)
                            }
                            .pickerStyle(.radioGroup)

                            Text(config.transcription.provider.caption)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            if config.transcription.provider == .openAICompatible {
                                TextField("Transcription Endpoint", text: $config.transcription.openAITranscriptionURL)
                                TextField("Model", text: $config.transcription.openAIModel)
                                TextField("API Key Env", text: $config.transcription.openAIAuthTokenEnv)
                            }
                        }
                        .padding(.top, 8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terminology Alignment")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("Import a TypeWhisper terminology snapshot to strengthen post-STT alignment for tool names, product names, and other technical terms without adding a second AI cleanup pass.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Import from TypeWhisper") {
                                switch onImportTypeWhisperTerminology(config) {
                                case .success(let updatedConfig):
                                    config = updatedConfig
                                    terminologyImportMessage = Self.terminologyStatusMessage(for: updatedConfig)
                                    terminologyImportIsError = false
                                case .failure(let error):
                                    terminologyImportMessage = error.localizedDescription
                                    terminologyImportIsError = true
                                }
                            }

                            Text("`transcription.hintTerms` still works for exact-only custom terms in `config.json`.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        if let terminologyImportMessage {
                            Text(terminologyImportMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(terminologyImportIsError ? .red : .secondary)
                        }
                    }
                }

                settingsCard(title: "Insertion") {
                    Toggle("Restore clipboard after paste", isOn: $config.injection.preserveClipboard)
                }

                HStack {
                    Button("Open Config Folder", action: onOpenConfigFolder)
                    Spacer()
                    Button("Save Settings") {
                        onSave(config)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, minHeight: 760)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityRefreshNonce += 1
        }
    }

    private static func terminologyStatusMessage(for config: AppConfig) -> String? {
        let importedEntries = config.transcription.terminology.importedEntries
        guard !importedEntries.isEmpty else {
            return nil
        }

        if let timestamp = config.transcription.terminology.lastImportedAt {
            return "Imported \(importedEntries.count) TypeWhisper terms at \(timestamp)."
        }

        return "Imported \(importedEntries.count) TypeWhisper terms."
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup Check")
                .font(.system(size: 13, weight: .semibold))
            setupRow(title: "Codex Desktop Login", status: hostStatus)
            setupRow(title: "Microphone", status: microphoneStatus)
            setupRow(title: "Accessibility", status: accessibilityStatus)
            if !AccessibilityPermission.isTrusted() {
                let guidance = AccessibilityPermission.repairGuidance()
                if let detail = guidance.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button("Request Accessibility Access") {
                        AccessibilityPermission.requestTrustIfNeeded()
                        accessibilityRefreshNonce += 1
                    }

                    Button("Open Accessibility Settings") {
                        AccessibilityPermission.openAccessibilitySettings()
                    }

                    Button("Refresh Status") {
                        accessibilityRefreshNonce += 1
                    }
                }
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Start")
                .font(.system(size: 13, weight: .semibold))
            Text("1. Install or open Codex on this Mac, then sign in with your ChatGPT account.")
            Text("2. Grant Microphone and Accessibility permissions.")
            Text("3. Put your cursor in Notes or Mail, press F5, speak for five seconds, then press F5 again.")
            Text("4. If Accessibility opens without a ChatType row, use the + button there to add the packaged ChatType.app, then return here and test again.")
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func setupRow(title: String, status: SetupStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.isReady ? .green : .orange)
                .font(.system(size: 14))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(status.title)
                    .font(.system(size: 12, weight: .medium))
                Text(status.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupStatus {
    let title: String
    let subtitle: String
    var isReady: Bool = true
}
