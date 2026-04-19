import AppKit
import AVFoundation
import Foundation
import OSLog

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
    private let authClient = CodexAuthClient()
    private let latencyRecorder = LatencyRecorder()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.longbiaochen.chattype",
        category: "Permissions"
    )

    private var config = AppConfig()
    private var hotkeyMonitor: HotkeyMonitor?
    private var recorder: AudioRecorder?
    private var statusMenu: StatusMenuController?
    private var preferencesWindowController: PreferencesWindowController?
    private var microphonePermissionWindowController: MicrophonePermissionWindowController?
    private var state: State = .idle
    private var recordingLevelTimer: Timer?
    private var overlayDemoFrameIndex = 0
    private var launchAppContext: LaunchAppContext?

    func start(launchMode: AppLaunchMode = .normal) {
        do {
            if let launchBlocker = AppInstallLocation.launchBlocker() {
                NSSound.beep()
                showInstallRequiredAlert(message: launchBlocker.message)
                notifier.notify(title: "ChatType install required", body: launchBlocker.message)
                AppInstallLocation.revealApplicationsFolder()
                NSApplication.shared.terminate(nil)
                return
            }

            statusMenu = StatusMenuController(
                openSettingsHandler: { [weak self] in self?.openSettings() },
                openConfigHandler: { [weak self] in self?.openConfigFolder() },
                quitHandler: { NSApplication.shared.terminate(nil) }
            )

            switch launchMode {
            case .normal:
                config = try configStore.load()
                recorder = AudioRecorder(sampleRateHz: config.transcription.sampleRateHz)
                refreshReadyState()
                prewarmAuthIfNeeded()

                hotkeyMonitor = try HotkeyMonitor(keyCode: config.transcription.hotkeyKeyCode) { [weak self] in
                    Task { @MainActor in
                        self?.handleHotkeyPress()
                    }
                }
                notifier.ensureAuthorization()
            case .overlayDemo:
                config = (try? configStore.load()) ?? AppConfig()
                runOverlayDemo()
                return
            case .benchmark:
                config = try configStore.load()
                Task {
                    defer { NSApplication.shared.terminate(nil) }
                    do {
                        let runner = BenchmarkRunner(
                            config: config,
                            authClient: authClient
                        )
                        try await runner.run()
                    } catch {
                        print("Benchmark failed: \(error.localizedDescription)")
                    }
                }
                return
            }
        } catch {
            NSSound.beep()
            notifier.notify(title: "ChatType launch failed", body: error.localizedDescription)
            statusMenu?.update(state: .error, detail: error.localizedDescription)
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

        logger.info("Start recording requested from hotkey")
        state = .processing
        statusMenu?.update(state: .processing, detail: "Requesting microphone")
        overlay.showRecording()

        Task { @MainActor in
            do {
                try await requestMicrophoneAccess()
                logger.info("Microphone access stage completed")

                let issues = RuntimePreflight.issues(
                    for: config,
                    environment: ProcessInfo.processInfo.environment
                )
                if let message = RuntimePreflight.summary(for: issues) {
                    logger.error("Runtime preflight blocked recording with \(issues.count, privacy: .public) issue(s): \(message, privacy: .public)")
                    stopRecordingLevelUpdates()
                    state = .idle
                    statusMenu?.update(state: .setupRequired, detail: message)
                    overlay.showError(message)
                    notifier.notify(title: "ChatType setup required", body: message)
                    openSettings()
                    return
                }

                logger.info("Runtime preflight passed; starting AVAudioRecorder")
                self.launchAppContext = LaunchAppContext.current()
                try await recorder.startRecording()
                logger.info("AVAudioRecorder started successfully")
                state = .recording
                statusMenu?.update(state: .recording, detail: "Recording on F5")
                startRecordingLevelUpdates()
            } catch {
                logger.error("Start recording failed: \(error.localizedDescription, privacy: .public)")
                stopRecordingLevelUpdates()
                state = .idle
                refreshReadyState(detailOverride: error.localizedDescription, state: .error)
                overlay.showError(error.localizedDescription)
                notifier.notify(title: "ChatType", body: error.localizedDescription)
            }
        }
    }

    private func stopRecording() {
        guard let recorder else { return }

        do {
            stopRecordingLevelUpdates()
            let audio = try recorder.stopRecording()
            state = .processing
            statusMenu?.update(state: .processing, detail: "Processing")
            overlay.showProcessing()

            let transcriptionConfig = config.transcription
            let injectionConfig = config.injection
            let processingStarted = DispatchTime.now().uptimeNanoseconds
            let launchAppContext = self.launchAppContext

            Task {
                let pipeline = DictationPipeline(
                    transcriber: ChatGPTTranscriber(
                        authClient: authClient,
                        config: transcriptionConfig
                    ),
                    normalizer: TerminologyNormalizer(),
                    importedEntries: transcriptionConfig.terminology.enabled ? transcriptionConfig.terminology.importedEntries : [],
                    hintTerms: transcriptionConfig.hintTerms
                )

                do {
                    let prepared = try await pipeline.prepare(audio: audio)

                    await MainActor.run {
                        do {
                            let injectStarted = DispatchTime.now().uptimeNanoseconds
                            let outcome = try injector.inject(
                                text: prepared.finalText,
                                preserveClipboard: injectionConfig.preserveClipboard,
                                restoreDelayMilliseconds: injectionConfig.restoreDelayMilliseconds,
                                launchAppContext: launchAppContext
                            )
                            let injectMs = elapsedMilliseconds(since: injectStarted)
                            let totalProcessingMs = elapsedMilliseconds(since: processingStarted)
                            recordLatency(
                                prepared: prepared,
                                outcome: outcome,
                                injectMs: injectMs,
                                totalProcessingMs: totalProcessingMs,
                                errorCategory: nil
                            )
                            state = .idle
                            statusMenu?.update(
                                state: .ready,
                                detail: statusDetail(for: outcome)
                            )
                            overlay.showResult(text: prepared.finalText, outcome: outcome)
                        } catch {
                            let totalProcessingMs = elapsedMilliseconds(since: processingStarted)
                            recordLatency(
                                prepared: prepared,
                                outcome: nil,
                                injectMs: 0,
                                totalProcessingMs: totalProcessingMs,
                                errorCategory: "inject"
                            )
                            stopRecordingLevelUpdates()
                            state = .idle
                            statusMenu?.update(state: .error, detail: error.localizedDescription)
                            overlay.showError(error.localizedDescription)
                            notifier.notify(title: "ChatType", body: error.localizedDescription)
                        }
                        self.launchAppContext = nil
                    }
                } catch {
                    await MainActor.run {
                        let totalProcessingMs = elapsedMilliseconds(since: processingStarted)
                        let sample = LatencySample(
                            timestamp: Date(),
                            audioDurationMs: audio.durationMs,
                            audioBytes: (try? Data(contentsOf: audio.fileURL).count) ?? 0,
                            provider: transcriptionConfig.provider.rawValue,
                            authMs: 0,
                            transcribeMs: 0,
                            normalizationMs: 0,
                            injectMs: 0,
                            totalProcessingMs: totalProcessingMs,
                            resultStatus: "error",
                            errorCategory: "transcribe"
                        )
                        try? latencyRecorder.record(sample)
                        stopRecordingLevelUpdates()
                        state = .idle
                        statusMenu?.update(state: .error, detail: error.localizedDescription)
                        overlay.showError(error.localizedDescription)
                        notifier.notify(title: "ChatType", body: error.localizedDescription)
                        self.launchAppContext = nil
                    }
                }

                try? FileManager.default.removeItem(at: audio.fileURL)
            }
        } catch {
            stopRecordingLevelUpdates()
            state = .idle
            statusMenu?.update(state: .error, detail: error.localizedDescription)
            overlay.showError(error.localizedDescription)
            notifier.notify(title: "ChatType", body: error.localizedDescription)
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
                        self.refreshReadyState(detailOverride: "Settings saved", state: .ready)
                        self.prewarmAuthIfNeeded()
                    } catch {
                        self.overlay.showError(error.localizedDescription)
                        self.notifier.notify(title: "ChatType", body: error.localizedDescription)
                    }
                },
                onImportTypeWhisperTerminology: { [weak self] currentConfig in
                    guard let self else {
                        return .failure(
                            NSError(
                                domain: "ChatType.Preferences",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "ChatType settings are no longer available."]
                            )
                        )
                    }

                    do {
                        let imported = try TypeWhisperTerminologyImporter().importEntries()
                        var updatedConfig = currentConfig
                        updatedConfig.transcription.terminology.enabled = true
                        updatedConfig.transcription.terminology.importedEntries = imported.entries
                        updatedConfig.transcription.terminology.lastImportedSource = imported.source
                        updatedConfig.transcription.terminology.lastImportedAt = imported.importedAt

                        try self.configStore.save(updatedConfig)
                        self.config = updatedConfig
                        self.refreshReadyState(
                            detailOverride: "Imported \(imported.entries.count) TypeWhisper terms",
                            state: .ready
                        )

                        return .success(updatedConfig)
                    } catch {
                        return .failure(error)
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

    private func showInstallRequiredAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Install ChatType to /Applications first"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func requestMicrophoneAccess() async throws {
        let status = AudioRecorder.microphonePermissionState()
        let previousActivationPolicy = NSApp.activationPolicy()

        logger.info(
            "Preparing microphone request with status=\(String(describing: status), privacy: .public) activationPolicy=\(String(describing: previousActivationPolicy), privacy: .public)"
        )

        if status == .undetermined {
            if previousActivationPolicy != .regular {
                logger.info("Temporarily switching activation policy to regular for first-run microphone prompt")
                _ = NSApp.setActivationPolicy(.regular)
            }

            let controller = microphonePermissionWindowController ?? MicrophonePermissionWindowController()
            microphonePermissionWindowController = controller
            logger.info("Presenting first-run microphone permission window")
            let shouldContinue = await controller.present()
            logger.info("First-run microphone permission window returned shouldContinue=\(shouldContinue, privacy: .public)")
            guard shouldContinue else {
                if previousActivationPolicy != .regular {
                    _ = NSApp.setActivationPolicy(previousActivationPolicy)
                }
                logger.error("User cancelled first-run microphone permission window")
                throw RecorderError.microphoneDenied
            }
        }

        defer {
            if previousActivationPolicy != .regular {
                logger.info("Restoring activation policy to \(String(describing: previousActivationPolicy), privacy: .public)")
                _ = NSApp.setActivationPolicy(previousActivationPolicy)
            }
        }

        logger.info("Calling microphone access request helper")
        try await AudioRecorder.ensureMicrophoneAccess()
    }

    private func runOverlayDemo() {
        let demoLevels: [CGFloat] = [0.14, 0.28, 0.46, 0.72, 0.54, 0.32, 0.18, 0.64]

        state = .processing
        statusMenu?.update(state: .demo, detail: "Overlay demo")
        overlay.showRecording()
        overlayDemoFrameIndex = 0

        recordingLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let level = demoLevels[self.overlayDemoFrameIndex % demoLevels.count]
                self.overlayDemoFrameIndex += 1
                self.overlay.updateRecordingLevel(level)
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self.stopRecordingLevelUpdates()
            self.overlay.showProcessing()

            try? await Task.sleep(nanoseconds: 1_300_000_000)
            self.overlay.showResult(text: "Demo", outcome: .pasted)

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.overlay.showError("Clipboard only")

            try? await Task.sleep(nanoseconds: 2_400_000_000)
            NSApplication.shared.terminate(nil)
        }
    }

    private func startRecordingLevelUpdates() {
        stopRecordingLevelUpdates()
        overlay.showRecording()

        recordingLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let level = self.recorder?.currentLevel() else {
                    return
                }
                self.overlay.updateRecordingLevel(level)
            }
        }
    }

    private func stopRecordingLevelUpdates() {
        recordingLevelTimer?.invalidate()
        recordingLevelTimer = nil
    }

    private func statusDetail(for outcome: InjectionOutcome) -> String {
        switch outcome {
        case .pasted:
            return "Pasted transcript"
        case .copiedToClipboard(let reason):
            return reason.statusDetail
        }
    }

    private func prewarmAuthIfNeeded() {
        guard config.transcription.provider == .codexChatGPTBridge else {
            return
        }

        Task.detached(priority: .utility) { [authClient] in
            try? authClient.prewarmChatGPTStatus()
        }
    }

    private func recordLatency(
        prepared: PreparedDictation,
        outcome: InjectionOutcome?,
        injectMs: Int,
        totalProcessingMs: Int,
        errorCategory: String?
    ) {
        let sample = LatencySample(
            timestamp: Date(),
            audioDurationMs: prepared.metrics.transcription.audioDurationMs,
            audioBytes: prepared.metrics.transcription.audioBytes,
            provider: prepared.metrics.transcription.provider.rawValue,
            authMs: prepared.metrics.transcription.authMs,
            transcribeMs: prepared.metrics.transcription.transcribeMs,
            normalizationMs: prepared.metrics.normalizationMs,
            injectMs: injectMs,
            totalProcessingMs: totalProcessingMs,
            resultStatus: latencyResultStatus(for: outcome),
            errorCategory: errorCategory
        )
        try? latencyRecorder.record(sample)
    }

    private func latencyResultStatus(for outcome: InjectionOutcome?) -> String {
        guard let outcome else {
            return "error"
        }

        switch outcome {
        case .pasted:
            return "pasted"
        case .copiedToClipboard:
            return "clipboard"
        }
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    private func refreshReadyState(detailOverride: String? = nil, state: StatusMenuVisualState = .ready) {
        let issues = RuntimePreflight.issues(
            for: config,
            environment: ProcessInfo.processInfo.environment
        )
        if let detailOverride {
            statusMenu?.update(state: state, detail: detailOverride)
        } else if let summary = RuntimePreflight.summary(for: issues) {
            statusMenu?.update(state: .setupRequired, detail: summary)
        } else {
            statusMenu?.update(state: state, detail: "Ready. Press F5 to dictate")
        }
    }
}
