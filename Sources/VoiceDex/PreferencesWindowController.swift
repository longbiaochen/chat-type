import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(
        config: AppConfig,
        onSave: @escaping (AppConfig) -> Void,
        onOpenConfigFolder: @escaping () -> Void
    ) {
        let view = PreferencesView(
            initialConfig: config,
            onSave: onSave,
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

    let onSave: (AppConfig) -> Void
    let onOpenConfigFolder: () -> Void

    init(
        initialConfig: AppConfig,
        onSave: @escaping (AppConfig) -> Void,
        onOpenConfigFolder: @escaping () -> Void
    ) {
        _config = State(initialValue: initialConfig)
        _showsAdvancedRecovery = State(initialValue: initialConfig.transcription.provider == .openAICompatible)
        self.onSave = onSave
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
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return SetupStatus(title: "Granted", subtitle: "Microphone access is ready.")
        case .notDetermined:
            return SetupStatus(title: "Not requested yet", subtitle: "Press F5 once and macOS will ask for microphone access.", isReady: false)
        case .denied, .restricted:
            return SetupStatus(title: "Needs permission", subtitle: "Enable microphone access in System Settings > Privacy & Security.", isReady: false)
        @unknown default:
            return SetupStatus(title: "Unknown", subtitle: "Check microphone access in System Settings.", isReady: false)
        }
    }

    private var accessibilityStatus: SetupStatus {
        if AXIsProcessTrusted() {
            return SetupStatus(title: "Granted", subtitle: "Auto-paste is ready.")
        }

        return SetupStatus(
            title: "Optional but recommended",
            subtitle: "Grant Accessibility to allow paste into the focused app. Without it, ChatType leaves text in your clipboard.",
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

                    Text("Advanced: if you need term preservation for filenames or product names, add `transcription.hintTerms` in config.json.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup Check")
                .font(.system(size: 13, weight: .semibold))
            setupRow(title: "Codex Desktop Login", status: hostStatus)
            setupRow(title: "Microphone", status: microphoneStatus)
            setupRow(title: "Accessibility", status: accessibilityStatus)
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
            Text("4. If you only see clipboard output, grant Accessibility and try again.")
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
