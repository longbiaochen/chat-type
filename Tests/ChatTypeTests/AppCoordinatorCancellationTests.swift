import CoreGraphics
import Foundation
import Testing
@testable import ChatType

@MainActor
private final class FakeCoordinatorRecorder: RecordingControlling {
    private(set) var cancelRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0
    var onStartRecording: (@Sendable () async -> Void)?
    var nextAudio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake.wav"),
        durationMs: 1_000
    )

    func startRecording() async throws {
        await onStartRecording?()
    }

    func stopRecording() throws -> RecordedAudio {
        stopRecordingCallCount += 1
        return nextAudio
    }

    func cancelRecording() throws {
        cancelRecordingCallCount += 1
    }

    func currentLevel() -> CGFloat? {
        0.25
    }
}

@MainActor
private final class FakeCoordinatorOverlay: OverlayControlling {
    var onCancel: (@MainActor () -> Void)?
    var onShowProcessing: (@MainActor () -> Void)?
    private(set) var hideCallCount = 0
    private(set) var recordingElapsedTexts: [String] = []
    private(set) var showProcessingCallCount = 0

    func showRecording(elapsedText: String) {
        recordingElapsedTexts.append(elapsedText)
    }
    func updateRecording(level: CGFloat, elapsedText: String) {}
    func showProcessing() {
        showProcessingCallCount += 1
        onShowProcessing?()
    }
    func showResult(text: String, outcome: InjectionOutcome) {}
    func showError(_ message: String) {}

    func hide() {
        hideCallCount += 1
    }
}

@MainActor
private final class FakeCoordinatorStatusMenu: StatusMenuUpdating {
    private(set) var updates: [(StatusMenuVisualState, String)] = []

    func update(state: StatusMenuVisualState, detail: String) {
        updates.append((state, detail))
    }
}

@MainActor
private final class FakeCoordinatorNotifier: NotificationDispatching {
    func ensureAuthorization() {}
    func notify(title: String, body: String) {}
}

@MainActor
private final class FakeCoordinatorInjector: TextInjecting {
    private(set) var injectCallCount = 0

    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?
    ) throws -> InjectionOutcome {
        injectCallCount += 1
        return .pasted
    }
}

private struct FakeCoordinatorPipeline: DictationPreparing {
    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        try? Data().write(to: audio.fileURL)
        return PreparedDictation(
            rawText: "raw",
            finalText: "final",
            normalizationApplied: false,
            exactReplacementCount: 0,
            fuzzyReplacementCount: 0,
            metrics: DictationMetrics(
                transcription: TranscriptionMetrics(
                    provider: .codexChatGPTBridge,
                    audioDurationMs: audio.durationMs,
                    audioBytes: 4,
                    authMs: 0,
                    transcribeMs: 0,
                    promptIncluded: false
                ),
                normalizationMs: 0
            )
        )
    }
}

private actor CoordinatorGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct BlockingCoordinatorPipeline: DictationPreparing {
    let gate: CoordinatorGate

    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        try? Data().write(to: audio.fileURL)
        await gate.wait()
        return PreparedDictation(
            rawText: "raw",
            finalText: "final",
            normalizationApplied: false,
            exactReplacementCount: 0,
            fuzzyReplacementCount: 0,
            metrics: DictationMetrics(
                transcription: TranscriptionMetrics(
                    provider: .codexChatGPTBridge,
                    audioDurationMs: audio.durationMs,
                    audioBytes: 4,
                    authMs: 0,
                    transcribeMs: 0,
                    promptIncluded: false
                ),
                normalizationMs: 0
            )
        )
    }
}

private struct FakeLatencyRecorder: LatencyRecording {
    func record(_ sample: LatencySample) throws {}
}

@MainActor
private func waitForCoordinatorState(
    _ coordinator: AppCoordinator,
    toBecome expectedState: AppCoordinator.State,
    attempts: Int = 100
) async {
    for _ in 0..<attempts where coordinator.state != expectedState {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
struct AppCoordinatorCancellationTests {
    @Test
    func cancelCurrentSessionDiscardsActiveRecordingAndResetsState() throws {
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authClient: CodexAuthClient(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _ in statusMenu },
            pipelineFactory: { _, _ in FakeCoordinatorPipeline() }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.state = AppCoordinator.State.recording
        coordinator.launchAppContext = LaunchAppContext(
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            processIdentifier: 123
        )

        coordinator.cancelCurrentSession()

        #expect(recorder.cancelRecordingCallCount == 1)
        #expect(coordinator.state == AppCoordinator.State.idle)
        #expect(coordinator.launchAppContext == nil)
        #expect(overlay.hideCallCount == 1)
        #expect(statusMenu.updates.last?.0 == .ready)
    }

    @Test
    func cancelCurrentSessionCancelsProcessingTaskWithoutInjecting() async throws {
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let injector = FakeCoordinatorInjector()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: injector,
            overlay: overlay,
            authClient: CodexAuthClient(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _ in statusMenu },
            pipelineFactory: { _, _ in FakeCoordinatorPipeline() }
        )

        let processingTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }

        coordinator.state = AppCoordinator.State.processing
        coordinator.statusMenu = statusMenu
        coordinator.processingTask = processingTask
        coordinator.launchAppContext = LaunchAppContext(
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            processIdentifier: 123
        )

        coordinator.cancelCurrentSession()
        await Task.yield()

        #expect(processingTask.isCancelled == true)
        #expect(injector.injectCallCount == 0)
        #expect(coordinator.state == AppCoordinator.State.idle)
        #expect(coordinator.processingTask == nil)
        #expect(coordinator.launchAppContext == nil)
        #expect(overlay.hideCallCount == 1)
        #expect(statusMenu.updates.last?.0 == .ready)
    }

    @Test
    func startRecordingCapturesLaunchContextBeforeProcessingOverlay() async throws {
        let startGate = CoordinatorGate()
        let recorder = FakeCoordinatorRecorder()
        recorder.onStartRecording = {
            await startGate.wait()
        }
        let capturedContext = LaunchAppContext(
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            processIdentifier: 123
        )
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        var contextWhenProcessing: LaunchAppContext?
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authClient: CodexAuthClient(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _ in statusMenu },
            pipelineFactory: { _, _ in FakeCoordinatorPipeline() },
            launchAppContextProvider: { capturedContext }
        )
        overlay.onShowProcessing = {
            contextWhenProcessing = coordinator.launchAppContext
        }

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu
        coordinator.handleHotkeyPress()

        #expect(contextWhenProcessing == capturedContext)
        #expect(overlay.showProcessingCallCount == 1)
        #expect(overlay.recordingElapsedTexts.isEmpty)

        coordinator.cancelCurrentSession()
        await startGate.resume()
    }

    @Test
    func secondHotkeyTransitionsRecordingSessionIntoProcessing() async throws {
        let processingGate = CoordinatorGate()
        let recorder = FakeCoordinatorRecorder()
        let overlay = FakeCoordinatorOverlay()
        let statusMenu = FakeCoordinatorStatusMenu()
        let coordinator = AppCoordinator(
            config: AppConfig(),
            notifier: FakeCoordinatorNotifier(),
            injector: FakeCoordinatorInjector(),
            overlay: overlay,
            authClient: CodexAuthClient(),
            latencyRecorder: FakeLatencyRecorder(),
            recorderFactory: { _ in recorder },
            statusMenuFactory: { _, _, _ in statusMenu },
            pipelineFactory: { _, _ in BlockingCoordinatorPipeline(gate: processingGate) }
        )

        coordinator.recorder = recorder
        coordinator.statusMenu = statusMenu

        coordinator.handleHotkeyPress()
        await waitForCoordinatorState(coordinator, toBecome: .recording)

        coordinator.handleHotkeyPress()
        await Task.yield()

        #expect(recorder.stopRecordingCallCount == 1)
        #expect(coordinator.state == AppCoordinator.State.processing)
        #expect(overlay.showProcessingCallCount >= 1)
        #expect(statusMenu.updates.last?.0 == .processing)

        await processingGate.resume()
    }
}
