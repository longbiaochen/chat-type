import AVFoundation
import AVFAudio
import CoreGraphics
import Foundation
import OSLog

struct RecordedAudio: Sendable {
    let fileURL: URL
    let durationMs: Int
}

enum MicrophonePermissionState: Sendable {
    case granted
    case undetermined
    case denied
}

enum RecorderError: LocalizedError {
    case microphoneDenied
    case recorderInitFailed
    case recorderStartFailed
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "没有麦克风权限，无法开始录音。"
        case .recorderInitFailed:
            return "无法初始化录音器。"
        case .recorderStartFailed:
            return "录音启动失败。"
        case .noActiveRecording:
            return "当前没有录音中的会话。"
        }
    }
}

@MainActor
final class AudioRecorder {
    typealias PermissionProvider = @Sendable () -> MicrophonePermissionState
    typealias PermissionRequester = @Sendable () async -> Bool

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.longbiaochen.chattype",
        category: "Permissions"
    )

    private let sampleRateHz: Int
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    init(sampleRateHz: Int) {
        self.sampleRateHz = sampleRateHz
    }

    nonisolated static func microphonePermissionState() -> MicrophonePermissionState {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .granted
            case .undetermined:
                return .undetermined
            case .denied:
                return .denied
            @unknown default:
                return .denied
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .undetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    nonisolated static func ensureMicrophoneAccess(
        permissionProvider: PermissionProvider = { microphonePermissionState() },
        requestPermission: @escaping PermissionRequester = {
            if #available(macOS 14.0, *) {
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }

            return await AVCaptureDevice.requestAccess(for: .audio)
        }
    ) async throws {
        let status = permissionProvider()
        logger.info("Microphone access check started with status: \(String(describing: status), privacy: .public)")

        switch status {
        case .granted:
            logger.info("Microphone access already authorized")
            return
        case .undetermined:
            logger.info("Microphone access not determined; requesting system prompt")
            let granted = await requestPermission()
            logger.info("Microphone access request returned granted=\(granted, privacy: .public)")
            guard granted else {
                throw RecorderError.microphoneDenied
            }
        case .denied:
            logger.error("Microphone access unavailable with status: \(String(describing: status), privacy: .public)")
            throw RecorderError.microphoneDenied
        @unknown default:
            logger.error("Microphone access hit unknown authorization status")
            throw RecorderError.microphoneDenied
        }
    }

    func startRecording() async throws {
        try await Self.ensureMicrophoneAccess()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chattype-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRateHz,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw RecorderError.recorderStartFailed
        }

        self.recorder = recorder
        self.fileURL = tempURL
    }

    func stopRecording() throws -> RecordedAudio {
        guard let recorder, let fileURL else {
            throw RecorderError.noActiveRecording
        }

        recorder.stop()
        self.recorder = nil
        self.fileURL = nil

        return RecordedAudio(
            fileURL: fileURL,
            durationMs: Int((recorder.currentTime * 1000).rounded())
        )
    }

    func currentLevel() -> CGFloat? {
        guard let recorder else {
            return nil
        }

        recorder.updateMeters()
        return WaveformNormalizer.normalizedLevel(
            fromAveragePower: recorder.averagePower(forChannel: 0)
        )
    }
}
