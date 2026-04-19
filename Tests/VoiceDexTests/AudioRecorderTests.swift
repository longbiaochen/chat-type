import AVFoundation
import Testing
@testable import ChatType

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
}
