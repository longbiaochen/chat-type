import Foundation

protocol Transcriber {
    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult
}

protocol TranscriptNormalizing {
    func normalize(text: String, hintTerms: [String]) -> NormalizationResult
}

struct DictationMetrics: Sendable, Equatable {
    let transcription: TranscriptionMetrics
    let normalizationMs: Int
}

struct PreparedDictation: Sendable, Equatable {
    let rawText: String
    let finalText: String
    let normalizationApplied: Bool
    let metrics: DictationMetrics
}

struct DictationPipeline {
    let transcriber: any Transcriber
    let normalizer: any TranscriptNormalizing
    let hintTerms: [String]

    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        let transcription = try await transcriber.transcribe(audio)
        let normalizationStarted = DispatchTime.now().uptimeNanoseconds
        let normalized = normalizer.normalize(
            text: transcription.text,
            hintTerms: hintTerms
        )
        let normalizationMs = elapsedMilliseconds(since: normalizationStarted)
        return PreparedDictation(
            rawText: transcription.text,
            finalText: normalized.text,
            normalizationApplied: normalized.applied,
            metrics: DictationMetrics(
                transcription: transcription.metrics,
                normalizationMs: normalizationMs
            )
        )
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}
