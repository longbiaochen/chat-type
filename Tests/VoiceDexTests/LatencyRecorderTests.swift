import Foundation
import Testing
@testable import ChatType

@Test
func latencyRecorderAppendsJsonlSamples() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let recorder = LatencyRecorder(directoryURL: root)

    try recorder.record(
        .init(
            timestamp: Date(timeIntervalSince1970: 1_234),
            audioDurationMs: 3_000,
            audioBytes: 42_000,
            provider: "codexChatGPTBridge",
            authMs: 120,
            transcribeMs: 850,
            normalizationMs: 2,
            injectMs: 40,
            totalProcessingMs: 1_012,
            resultStatus: "pasted",
            errorCategory: nil
        )
    )

    let contents = try String(contentsOf: root.appendingPathComponent("latency.jsonl"), encoding: .utf8)
    #expect(contents.contains("\"provider\":\"codexChatGPTBridge\""))
    #expect(contents.contains("\"transcribeMs\":850"))
}
