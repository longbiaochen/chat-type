import Foundation
import Testing
@testable import ChatType

@Test
func recoveryStoreArchivesAudioAndLoadsNewestTenRecords() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = RecoveryStore(directoryURL: root)

    for index in 0..<12 {
        let audioURL = root.appendingPathComponent("source-\(index).wav")
        try Data("audio-\(index)".utf8).write(to: audioURL)
        try store.record(
            RecoveryRecordInput(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                sourceAudioURL: audioURL,
                durationMs: index * 100,
                asrText: "asr-\(index)",
                polishText: "polish-\(index)",
                appName: "Editor",
                appBundleIdentifier: "com.example.editor",
                outcome: "pasted",
                errorMessage: nil
            )
        )
    }

    let records = try store.loadRecent(limit: 20)

    #expect(records.count == 10)
    #expect(records.map(\.asrText) == (2..<12).map { "asr-\($0)" })
    #expect(records.last?.polishText == "polish-11")
    #expect(records.last?.audioDurationMs == 1_100)
    let newestAudioURL = try #require(records.last?.audioURL(baseDirectory: root))
    #expect((try? Data(contentsOf: newestAudioURL)) == Data("audio-11".utf8))
}

@Test
func recoveryRecordPreviewsReturnSeparateAudioASRAndPolishItems() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = RecoveryStore(directoryURL: root)
    let audioURL = root.appendingPathComponent("source.wav")
    try Data("voice".utf8).write(to: audioURL)
    try store.record(
        RecoveryRecordInput(
            timestamp: Date(timeIntervalSince1970: 42),
            sourceAudioURL: audioURL,
            durationMs: 3_000,
            asrText: "raw words",
            polishText: "polished words",
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            outcome: "clipboard",
            errorMessage: nil
        )
    )

    let record = try #require(try store.loadRecent(limit: 10).first)

    #expect(RecoveryHistoryPreview.recentItems(from: [record], kind: .audio, limit: 10).first?.copyKind == .audioFile)
    #expect(RecoveryHistoryPreview.recentItems(from: [record], kind: .asr, limit: 10).first?.copyText == "raw words")
    #expect(RecoveryHistoryPreview.recentItems(from: [record], kind: .polish, limit: 10).first?.copyText == "polished words")
}
