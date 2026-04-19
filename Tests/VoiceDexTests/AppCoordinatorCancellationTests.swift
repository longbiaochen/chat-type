import CoreGraphics
import Foundation
import Testing
@testable import ChatType

@MainActor
private final class FakeCoordinatorRecorder: RecordingControlling {
    private(set) var cancelRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0
    var nextAudio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake.wav"),
        durationMs: 1_000
    )

    func startRecording() async throws {}

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
    private(set) var hideCallCount = 0

    func showRecording(elapsedText: String) {}
    func updateRecording(level: CGFloat, elapsedText: String) {}
    func showProcessing() {}
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
        PreparedDictation(
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
}
