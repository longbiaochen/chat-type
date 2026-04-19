import AppKit
import AVFoundation
import Foundation
import OSLog

@MainActor
final class AppCoordinator {
    enum State: Equatable {
        case idle
        case recording
        case processing
    }

    typealias RecorderFactory = @MainActor (Int) -> any RecordingControlling
    typealias StatusMenuFactory = @MainActor (
        @escaping () -> Void,
        @escaping () -> Void,
        @escaping () -> Void
    ) -> any StatusMenuUpdating
    typealias PipelineFactory = @Sendable (TranscriptionConfig, CodexAuthClient) -> any DictationPreparing

    let configStore: ConfigStore
    let notifier: any NotificationDispatching
    let injector: any TextInjecting
    let overlay: any OverlayControlling
    let authClient: CodexAuthClient
    let latencyRecorder: any LatencyRecording
    let recorderFactory: RecorderFactory
    let statusMenuFactory: StatusMenuFactory
    let pipelineFactory: PipelineFactory
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.longbiaochen.chattype",
        category: "Permissions"
    )

    var config: AppConfig
    private var hotkeyMonitor: HotkeyMonitor?
    var recorder: (any RecordingControlling)?
    var statusMenu: (any StatusMenuUpdating)?
    private var preferencesWindowController: PreferencesWindowController?
    private var microphonePermissionWindowController: MicrophonePermissionWindowController?
    var state: State = .idle
    private var recordingLevelTimer: Timer?
    private var overlayDemoFrameIndex = 0
    var launchAppContext: LaunchAppContext?
    var processingTask: Task<Void, Never>?
    private var startRecordingTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var recordingStartedAt: DispatchTime?

    init(
        configStore: ConfigStore = ConfigStore(),
        config: AppConfig = AppConfig(),
        notifier: any NotificationDispatching = Notifier(),
        injector: any TextInjecting = TextInjector(),
        overlay: (any OverlayControlling)? = nil,
        authClient: CodexAuthClient = CodexAuthClient(),
        latencyRecorder: any LatencyRecording = LatencyRecorder(),
        recorderFactory: @escaping RecorderFactory = { AudioRecorder(sampleRateHz: $0) },
        statusMenuFactory: @escaping StatusMenuFactory = { openSettings, openConfig, quit in
            StatusMenuController(
                openSettingsHandler: openSettings,
                openConfigHandler: openConfig,
                quitHandler: quit
            )
        },
        pipelineFactory: @escaping PipelineFactory = { transcriptionConfig, authClient in
            DictationPipeline(
                transcriber: ChatGPTTranscriber(
                    authClient: authClient,
                    config: transcriptionConfig
                ),
                normalizer: TerminologyNormalizer(),
                importedEntries: transcriptionConfig.terminology.enabled ? transcriptionConfig.terminology.importedEntries : [],
                hintTerms: transcriptionConfig.hintTerms
            )
        }
    ) {
        self.configStore = configStore
        self.config = config
        self.notifier = notifier
        self.injector = injector
        let resolvedOverlay = overlay ?? OverlayController()
        self.overlay = resolvedOverlay
        self.authClient = authClient
        self.latencyRecorder = latencyRecorder
        self.recorderFactory = recorderFactory
        self.statusMenuFactory = statusMenuFactory
        self.pipelineFactory = pipelineFactory
        self.overlay.onCancel = { [weak self] in
            self?.cancelCurrentSession()
        }
    }

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

            statusMenu = statusMenuFactory(
                { [weak self] in self?.openSettings() },
                { [weak self] in self?.openConfigFolder() },
                { NSApplication.shared.terminate(nil) }
            )

            switch launchMode {
            case .normal:
                config = try configStore.load()
                recorder = recorderFactory(config.transcription.sampleRateHz)
                refreshReadyState()
                prewarmAuthIfNeeded()

                hotkeyMonitor = try HotkeyMonitor(keyCode: config.transcription.hotkeyKeyCode) { [weak self] in
                    Task { @MainActor in
                        self?.handleHotkeyPress()
                    }
                }
                notifier.ensureAuthorization()
            case .overlayDemo:
                config = (try? configStore.load()) ?? config
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

    func handleHotkeyPress() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            NSSound.beep()
        }
    }

    func cancelCurrentSession() {
        guard state != .idle || activeSessionID != nil || processingTask != nil || startRecordingTask != nil else {
            return
        }

        startRecordingTask?.cancel()
        startRecordingTask = nil
        processingTask?.cancel()
        processingTask = nil
        stopRecordingLevelUpdates()

        if state == .recording {
            try? recorder?.cancelRecording()
        }

        state = .idle
        activeSessionID = nil
        recordingStartedAt = nil
        launchAppContext = nil
        overlay.hide()
        refreshReadyState()
    }

    private func startRecording() {
        guard let recorder else { return }

        logger.info("Start recording requested from hotkey")
        let sessionID = UUID()
        activeSessionID = sessionID
        state = .processing
        statusMenu?.update(state: .processing, detail: "Requesting microphone")
        overlay.showRecording(elapsedText: "00:00")

        startRecordingTask?.cancel()
        startRecordingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.requestMicrophoneAccess()
                guard self.shouldContinue(sessionID: sessionID) else { return }
                logger.info("Microphone access stage completed")

                let issues = RuntimePreflight.issues(
                    for: self.config,
                    environment: ProcessInfo.processInfo.environment
                )
                if let message = RuntimePreflight.summary(for: issues) {
                    logger.error("Runtime preflight blocked recording with \(issues.count, privacy: .public) issue(s): \(message, privacy: .public)")
                    self.stopRecordingLevelUpdates()
                    self.state = .idle
                    self.activeSessionID = nil
                    self.statusMenu?.update(state: .setupRequired, detail: message)
                    self.overlay.showError(message)
                    self.notifier.notify(title: "ChatType setup required", body: message)
                    self.openSettings()
                    return
                }

                logger.info("Runtime preflight passed; starting recording session")
                self.launchAppContext = LaunchAppContext.current()
                try await recorder.startRecording()
                guard self.shouldContinue(sessionID: sessionID) else {
                    try? recorder.cancelRecording()
                    return
                }

                logger.info("Recording session started successfully")
                self.recordingStartedAt = .now()
                self.state = .recording
                self.statusMenu?.update(state: .recording, detail: "Recording on F5")
                self.startRecordingLevelUpdates()
            } catch is CancellationError {
                self.cancelCurrentSession()
            } catch {
                guard self.shouldContinue(sessionID: sessionID) else { return }
                logger.error("Start recording failed: \(error.localizedDescription, privacy: .public)")
                self.stopRecordingLevelUpdates()
                self.state = .idle
                self.activeSessionID = nil
                self.recordingStartedAt = nil
                self.refreshReadyState(detailOverride: error.localizedDescription, state: .error)
                self.overlay.showError(error.localizedDescription)
                self.notifier.notify(title: "ChatType", body: error.localizedDescription)
                self.launchAppContext = nil
            }

            if self.activeSessionID == sessionID {
                self.startRecordingTask = nil
            }
        }
    }

    private func stopRecording() {
        guard let recorder, let sessionID = activeSessionID else { return }

        do {
            stopRecordingLevelUpdates()
            let audio = try recorder.stopRecording()
            recordingStartedAt = nil
            state = .processing
            statusMenu?.update(state: .processing, detail: "Processing")
            overlay.showProcessing()

            let transcriptionConfig = config.transcription
            let injectionConfig = config.injection
            let processingStarted = DispatchTime.now().uptimeNanoseconds
            let launchAppContext = self.launchAppContext

            processingTask?.cancel()
            processingTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    try? FileManager.default.removeItem(at: audio.fileURL)
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.activeSessionID == sessionID || self.activeSessionID == nil {
                            self.processingTask = nil
                        }
                    }
                }

                let pipeline = self.pipelineFactory(transcriptionConfig, self.authClient)

                do {
                    let prepared = try await pipeline.prepare(audio: audio)
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard self.shouldContinue(sessionID: sessionID) else { return }

                        do {
                            let injectStarted = DispatchTime.now().uptimeNanoseconds
                            let outcome = try self.injector.inject(
                                text: prepared.finalText,
                                preserveClipboard: injectionConfig.preserveClipboard,
                                restoreDelayMilliseconds: injectionConfig.restoreDelayMilliseconds,
                                launchAppContext: launchAppContext
                            )
                            let injectMs = self.elapsedMilliseconds(since: injectStarted)
                            let totalProcessingMs = self.elapsedMilliseconds(since: processingStarted)
                            self.recordLatency(
                                prepared: prepared,
                                outcome: outcome,
                                injectMs: injectMs,
                                totalProcessingMs: totalProcessingMs,
                                errorCategory: nil
                            )
                            self.state = .idle
                            self.activeSessionID = nil
                            self.statusMenu?.update(
                                state: .ready,
                                detail: self.statusDetail(for: outcome)
                            )
                            self.overlay.showResult(text: prepared.finalText, outcome: outcome)
                            self.launchAppContext = nil
                        } catch {
                            let totalProcessingMs = self.elapsedMilliseconds(since: processingStarted)
                            self.recordLatency(
                                prepared: prepared,
                                outcome: nil,
                                injectMs: 0,
                                totalProcessingMs: totalProcessingMs,
                                errorCategory: "inject"
                            )
                            self.state = .idle
                            self.activeSessionID = nil
                            self.statusMenu?.update(state: .error, detail: error.localizedDescription)
                            self.overlay.showError(error.localizedDescription)
                            self.notifier.notify(title: "ChatType", body: error.localizedDescription)
                            self.launchAppContext = nil
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }

                    await MainActor.run {
                        guard self.shouldContinue(sessionID: sessionID) else { return }

                        let totalProcessingMs = self.elapsedMilliseconds(since: processingStarted)
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
                        try? self.latencyRecorder.record(sample)
                        self.state = .idle
                        self.activeSessionID = nil
                        self.statusMenu?.update(state: .error, detail: error.localizedDescription)
                        self.overlay.showError(error.localizedDescription)
                        self.notifier.notify(title: "ChatType", body: error.localizedDescription)
                        self.launchAppContext = nil
                    }
                }
            }
        } catch {
            stopRecordingLevelUpdates()
            state = .idle
            activeSessionID = nil
            recordingStartedAt = nil
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
        overlay.showRecording(elapsedText: "00:00")
        overlayDemoFrameIndex = 0

        recordingLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let level = demoLevels[self.overlayDemoFrameIndex % demoLevels.count]
                self.overlayDemoFrameIndex += 1
                self.overlay.updateRecording(level: level, elapsedText: self.demoElapsedText())
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
        overlay.showRecording(elapsedText: elapsedRecordingText())

        recordingLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let level = self.recorder?.currentLevel() else {
                    return
                }
                self.overlay.updateRecording(level: level, elapsedText: self.elapsedRecordingText())
            }
        }
    }

    private func stopRecordingLevelUpdates() {
        recordingLevelTimer?.invalidate()
        recordingLevelTimer = nil
    }

    private func elapsedRecordingText() -> String {
        guard let recordingStartedAt else {
            return "00:00"
        }
        let elapsedSeconds = Int((DispatchTime.now().uptimeNanoseconds - recordingStartedAt.uptimeNanoseconds) / 1_000_000_000)
        return Self.formatElapsed(seconds: elapsedSeconds)
    }

    private func demoElapsedText() -> String {
        Self.formatElapsed(seconds: overlayDemoFrameIndex / 12)
    }

    private static func formatElapsed(seconds: Int) -> String {
        let boundedSeconds = max(0, seconds)
        return String(format: "%02d:%02d", boundedSeconds / 60, boundedSeconds % 60)
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

    private func shouldContinue(sessionID: UUID) -> Bool {
        activeSessionID == sessionID
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
