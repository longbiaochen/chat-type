import Foundation
import Testing
@testable import ChatType

@Test
func transcriptionHistoryRecorderStoresSuccessfulTextWithoutAudio() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let recorder = TranscriptionHistoryRecorder(directoryURL: root)

    try recorder.record(
        TranscriptionHistoryRecord(
            timestamp: Date(timeIntervalSince1970: 1_777_777_777),
            rawText: "open claw 和 type whisper 都要写对。",
            finalText: "OpenClaw 和 TypeWhisper 都要写对。",
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            outcome: "pasted",
            textPolishProvider: nil
        )
    )

    let historyURL = root.appendingPathComponent("transcription-history.jsonl")
    let contents = try String(contentsOf: historyURL, encoding: .utf8)
    #expect(contents.contains("OpenClaw"))
    #expect(contents.contains("com.openai.codex"))
    #expect(contents.contains(".wav") == false)
}

@Test
func transcriptionHistoryPreviewShowsNewestRecordsFirst() {
    let records = [
        TranscriptionHistoryRecord(
            timestamp: Date(timeIntervalSince1970: 100),
            rawText: "旧的原始记录",
            finalText: "旧的记录\n第二行",
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            outcome: "pasted",
            textPolishProvider: nil
        ),
        TranscriptionHistoryRecord(
            timestamp: Date(timeIntervalSince1970: 200),
            rawText: "最新原始记录",
            finalText: "最新的长记录" + String(repeating: "很长", count: 80),
            appName: nil,
            appBundleIdentifier: nil,
            outcome: "copied",
            textPolishProvider: "chatGPTAuth"
        ),
    ]

    let previews = TranscriptionHistoryPreview.recentItems(from: records, limit: 2)

    #expect(previews.map(\.outcome) == ["copied", "pasted"])
    #expect(previews[0].target == "Unknown target")
    #expect(previews[0].text.count <= 123)
    #expect(previews[0].text.hasSuffix("..."))
    #expect(previews[1].target == "Codex")
    #expect(previews[1].text == "旧的记录 第二行")
}

@Test
func transcriptionHistoryPreviewCanShowDictationOrPolishText() {
    let records = [
        TranscriptionHistoryRecord(
            timestamp: Date(timeIntervalSince1970: 100),
            rawText: "呃先打开冰箱",
            finalText: "- 第一步：打开冰箱",
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            outcome: "pasted",
            textPolishProvider: "chatGPTAuth"
        ),
        TranscriptionHistoryRecord(
            timestamp: Date(timeIntervalSince1970: 90),
            rawText: "只转写不润色",
            finalText: "只转写不润色",
            appName: "Notes",
            appBundleIdentifier: "com.apple.Notes",
            outcome: "copied",
            textPolishProvider: nil
        ),
    ]

    let dictation = TranscriptionHistoryPreview.recentItems(from: records, limit: 5, textSource: .dictation)
    let polish = TranscriptionHistoryPreview.recentItems(from: records, limit: 5, textSource: .polish)

    #expect(dictation.map(\.text) == ["呃先打开冰箱", "只转写不润色"])
    #expect(dictation.map(\.copyText) == ["呃先打开冰箱", "只转写不润色"])
    #expect(polish.map(\.text) == ["- 第一步：打开冰箱", "只转写不润色"])
    #expect(polish.first?.copyText == "- 第一步：打开冰箱")
    #expect(polish[1].copyText == "只转写不润色")
}

@Test
func terminologyLearnerSuggestsHighFrequencyTechnicalTermsOnly() throws {
    let records = [
        TranscriptionHistoryRecord(
            timestamp: Date(),
            rawText: nil,
            finalText: "OpenClaw TypeWhisper Codex https://example.com /tmp/file 普通中文",
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            outcome: "pasted",
            textPolishProvider: nil
        ),
        TranscriptionHistoryRecord(
            timestamp: Date(),
            rawText: nil,
            finalText: "OpenClaw TypeWhisper Codex 邮箱 test@example.com",
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            outcome: "copied",
            textPolishProvider: nil
        ),
        TranscriptionHistoryRecord(
            timestamp: Date(),
            rawText: nil,
            finalText: "OpenClaw TypeWhisper Codex",
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            outcome: "pasted",
            textPolishProvider: nil
        ),
    ]

    let suggestions = TerminologyLearner().suggestions(
        from: records,
        existingEntries: [
            TerminologyEntry(
                type: .term,
                original: "Codex",
                replacement: nil,
                aliases: [],
                isEnabled: true,
                source: "user",
                usageCount: 0,
                createdAt: "2026-05-07T10:00:00Z"
            ),
        ],
        minimumCount: 2
    )

    #expect(suggestions.map(\.original) == ["OpenClaw", "TypeWhisper"])
    #expect(suggestions.allSatisfy { $0.type == .suggestion && $0.isEnabled == false })
    #expect(suggestions.contains(where: { $0.original.contains("example") }) == false)
    #expect(suggestions.contains(where: { $0.original == "普通中文" }) == false)
}
