import AVFoundation
import Testing
@testable import ChatType

private final class FakeRecordingSession: RecordingSessionControlling, @unchecked Sendable {
    var prepareToRecordResult = true
    var recordResult = true
    private(set) var stopCallCount = 0
    var currentTime: TimeInterval = 1.25
    var averagePowerValue: Float = -30

    func prepareToRecord() -> Bool {
        prepareToRecordResult
    }

    func record() -> Bool {
        recordResult
    }

    func stop() {
        stopCallCount += 1
    }

    func updateMeters() {}

    func averagePower(forChannel channelNumber: Int) -> Float {
        averagePowerValue
    }
}

private actor AccessRequestProbe {
    private var requested = false

    func markRequested() {
        requested = true
    }

    func wasRequested() -> Bool {
        requested
    }
}

struct AudioRecorderTests {
    @Test
    func microphoneAccessRequestsSystemPromptWhenStatusIsUndetermined() async throws {
        let probe = AccessRequestProbe()

        try await AudioRecorder.ensureMicrophoneAccess(
            permissionProvider: { .undetermined },
            requestPermission: {
                await probe.markRequested()
                return true
            }
        )

        #expect(await probe.wasRequested())
    }

    @Test
    func microphoneAccessSkipsSystemPromptWhenAlreadyAuthorized() async throws {
        let probe = AccessRequestProbe()

        try await AudioRecorder.ensureMicrophoneAccess(
            permissionProvider: { .granted },
            requestPermission: {
                await probe.markRequested()
                return true
            }
        )

        #expect(!(await probe.wasRequested()))
    }

    @Test
    func microphoneAccessFailsImmediatelyWhenDenied() async {
        let probe = AccessRequestProbe()

        await #expect(throws: RecorderError.microphoneDenied) {
            try await AudioRecorder.ensureMicrophoneAccess(
                permissionProvider: { .denied },
                requestPermission: {
                    await probe.markRequested()
                    return false
                }
            )
        }

        #expect(!(await probe.wasRequested()))
    }

    @MainActor
    @Test
    func cancelRecordingDiscardsActiveSessionAndDeletesTempFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-recording-test.wav")
        try Data("wave".utf8).write(to: fileURL)

        let session = FakeRecordingSession()
        let recorder = AudioRecorder(
            sampleRateHz: 16_000,
            permissionProvider: { .granted },
            permissionRequester: { true },
            sessionFactory: { _, _ in session },
            temporaryFileURLFactory: { fileURL },
            fileManager: .default
        )

        try await recorder.startRecording()
        try recorder.cancelRecording()

        #expect(session.stopCallCount == 1)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)

        #expect(throws: RecorderError.noActiveRecording) {
            try recorder.stopRecording()
        }
    }
}
