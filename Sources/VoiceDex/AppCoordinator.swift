import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    private enum State {
        case idle
        case recording
        case processing
    }

    private let configStore = ConfigStore()
    private let notifier = Notifier()
    private let injector = TextInjector()
    private let overlay = OverlayController()

    private var config = AppConfig()
    private var hotkeyMonitor: HotkeyMonitor?
    private var recorder: AudioRecorder?
    private var statusMenu: StatusMenuController?
    private var preferencesWindowController: PreferencesWindowController?
    private var state: State = .idle

    func start() {
        do {
            config = try configStore.load()
            recorder = AudioRecorder(sampleRateHz: config.transcription.sampleRateHz)

            statusMenu = StatusMenuController(
                openSettingsHandler: { [weak self] in self?.openSettings() },
                openConfigHandler: { [weak self] in self?.openConfigFolder() },
                quitHandler: { NSApplication.shared.terminate(nil) }
            )
            statusMenu?.update(stateLabel: "vd", detail: "Ready")

            hotkeyMonitor = try HotkeyMonitor(keyCode: config.transcription.hotkeyKeyCode) { [weak self] in
                Task { @MainActor in
                    self?.handleHotkeyPress()
                }
            }
            notifier.ensureAuthorization()
        } catch {
            NSSound.beep()
            notifier.notify(title: "voice-dex launch failed", body: error.localizedDescription)
            statusMenu?.update(stateLabel: "ERR", detail: error.localizedDescription)
        }
    }

    private func handleHotkeyPress() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            NSSound.beep()
        }
    }

    private func startRecording() {
        guard let recorder else { return }
        if let message = RuntimePreflight.summary(
            for: RuntimePreflight.issues(
                for: config,
                environment: ProcessInfo.processInfo.environment
            )
        ) {
            state = .idle
            statusMenu?.update(stateLabel: "ERR", detail: "Fix settings before recording")
            overlay.showError(message)
            notifier.notify(title: "voice-dex setup required", body: message)
            return
        }

        state = .processing
        statusMenu?.update(stateLabel: "…", detail: "Requesting microphone")
        overlay.showRecording()

        Task { @MainActor in
            do {
                try await recorder.startRecording()
                state = .recording
                statusMenu?.update(stateLabel: "REC", detail: "Recording on F5")
            } catch {
                state = .idle
                statusMenu?.update(stateLabel: "vd", detail: error.localizedDescription)
                overlay.showError(error.localizedDescription)
                notifier.notify(title: "voice-dex", body: error.localizedDescription)
            }
        }
    }

    private func stopRecording() {
        guard let recorder else { return }

        do {
            let audio = try recorder.stopRecording()
            state = .processing
            statusMenu?.update(stateLabel: "…", detail: "Transcribing")
            overlay.showProcessing(provider: config.transcription.provider.title)

            let transcriptionConfig = config.transcription
            let cleanupConfig = config.cleanup
            let injectionConfig = config.injection

            Task.detached {
                let transcriber = ChatGPTTranscriber(
                    authClient: CodexAuthClient(),
                    config: transcriptionConfig
                )
                let postProcessor = TextPostProcessor(cleanup: cleanupConfig)

                do {
                    let rawText = try await transcriber.transcribe(audio)
                    let finalText = try await postProcessor.processIfNeeded(rawText)

                    await MainActor.run {
                        do {
                            let outcome = try self.injector.inject(
                                text: finalText,
                                preserveClipboard: injectionConfig.preserveClipboard,
                                restoreDelayMilliseconds: injectionConfig.restoreDelayMilliseconds
                            )
                            self.state = .idle
                            switch outcome {
                            case .pasted:
                                self.statusMenu?.update(stateLabel: "vd", detail: "Pasted into the focused app")
                            case .copiedToClipboard(let reason):
                                self.statusMenu?.update(stateLabel: "vd", detail: reason.statusDetail)
                            }
                            self.overlay.showResult(text: finalText, outcome: outcome)
                        } catch {
                            self.state = .idle
                            self.statusMenu?.update(stateLabel: "ERR", detail: error.localizedDescription)
                            self.overlay.showError(error.localizedDescription)
                            self.notifier.notify(title: "voice-dex", body: error.localizedDescription)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .idle
                        self.statusMenu?.update(stateLabel: "ERR", detail: error.localizedDescription)
                        self.overlay.showError(error.localizedDescription)
                        self.notifier.notify(title: "voice-dex", body: error.localizedDescription)
                    }
                }

                try? FileManager.default.removeItem(at: audio.fileURL)
            }
        } catch {
            state = .idle
            statusMenu?.update(stateLabel: "ERR", detail: error.localizedDescription)
            overlay.showError(error.localizedDescription)
            notifier.notify(title: "voice-dex", body: error.localizedDescription)
        }
    }

    private func openSettings() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                config: config,
                onSave: { [weak self] newConfig in
                    guard let self else { return }
                    do {
                        try self.configStore.save(newConfig)
                        self.config = newConfig
                        self.statusMenu?.update(stateLabel: "vd", detail: "Settings saved")
                    } catch {
                        self.overlay.showError(error.localizedDescription)
                        self.notifier.notify(title: "voice-dex", body: error.localizedDescription)
                    }
                },
                onOpenConfigFolder: { [weak self] in
                    self?.openConfigFolder()
                }
            )
        }

        preferencesWindowController?.show()
    }

    private func openConfigFolder() {
        let directoryURL = configStore.directoryURL
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directoryURL)
    }
}
