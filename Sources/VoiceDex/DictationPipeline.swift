import Foundation

protocol Transcriber {
    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult
}

protocol TranscriptNormalizing {
    func normalize(
        text: String,
        importedEntries: [TerminologyEntry],
        hintTerms: [String]
    ) -> NormalizationResult
}

struct DictationMetrics: Sendable, Equatable {
    let transcription: TranscriptionMetrics
    let normalizationMs: Int
}

struct PreparedDictation: Sendable, Equatable {
    let rawText: String
    let finalText: String
    let normalizationApplied: Bool
    let exactReplacementCount: Int
    let fuzzyReplacementCount: Int
    let metrics: DictationMetrics
}

struct DictationPipeline {
    let transcriber: any Transcriber
    let normalizer: any TranscriptNormalizing
    let importedEntries: [TerminologyEntry]
    let hintTerms: [String]

    func prepare(audio: RecordedAudio) async throws -> PreparedDictation {
        let transcription = try await transcriber.transcribe(audio)
        let normalizationStarted = DispatchTime.now().uptimeNanoseconds
        let normalized = normalizer.normalize(
            text: transcription.text,
            importedEntries: importedEntries,
            hintTerms: hintTerms
        )
        let normalizationMs = elapsedMilliseconds(since: normalizationStarted)
        return PreparedDictation(
            rawText: transcription.text,
            finalText: normalized.text,
            normalizationApplied: normalized.applied,
            exactReplacementCount: normalized.exactReplacementCount,
            fuzzyReplacementCount: normalized.fuzzyReplacementCount,
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
