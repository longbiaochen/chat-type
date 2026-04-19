import Foundation
import Testing
@testable import ChatType

private let acceptanceTranscript = "王老师 呃 我们这周三下午三点应该可以开会 你帮我发个邮件给大家 主题就是第二版预算 review 然后附件是 budget v2.xlsx"

private struct FakeTranscriber: Transcriber {
    let result: TranscriptionResult

    func transcribe(_ audio: RecordedAudio) async throws -> TranscriptionResult {
        result
    }
}

@Test
func terminologyNormalizerPreservesHintTermsWithoutModelRewrite() {
    let result = TerminologyNormalizer().normalize(
        text: "请帮我把 Budget V2.XLSX 发给大家 review 一下，顺便提一下 chattype 已经能用了。",
        importedEntries: [],
        hintTerms: ["budget v2.xlsx", "review", "ChatType"]
    )

    #expect(result.text.contains("budget v2.xlsx"))
    #expect(result.text.contains("review"))
    #expect(result.text.contains("ChatType"))
    #expect(result.applied == true)
    #expect(result.exactReplacementCount == 2)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerConvertsTraditionalChineseToSimplifiedChinese() {
    let result = TerminologyNormalizer().normalize(
        text: "請把這個檔案發過來，體驗一下 chattype。",
        importedEntries: [],
        hintTerms: ["ChatType"]
    )

    #expect(result.text == "请把这个档案发过来，体验一下 ChatType。")
    #expect(result.applied == true)
}

@Test
func terminologyNormalizerReplacesImportedAliasesAndSeparators() {
    let result = TerminologyNormalizer().normalize(
        text: "把 Type Whisper 和 open ai compatible 都写对。",
        importedEntries: [
            TerminologyEntry(
                canonical: "TypeWhisper",
                aliases: ["Type Whisper"],
                caseSensitive: true
            ),
            TerminologyEntry(
                canonical: "OpenAI Compatible",
                aliases: ["Open AI Compatible"],
                caseSensitive: true
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "把 TypeWhisper 和 OpenAI Compatible 都写对。")
    #expect(result.exactReplacementCount == 2)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func terminologyNormalizerFuzzilyAlignsImportedTechnicalTerms() {
    let result = TerminologyNormalizer().normalize(
        text: "Takwiisper 这次能不能和 Codex 对齐？",
        importedEntries: [
            TerminologyEntry(
                canonical: "TypeWhisper",
                aliases: ["Type Whisper"],
                caseSensitive: true
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "TypeWhisper 这次能不能和 Codex 对齐？")
    #expect(result.exactReplacementCount == 0)
    #expect(result.fuzzyReplacementCount == 1)
}

@Test
func terminologyNormalizerAvoidsFuzzyRewritesInsideProtectedLiterals() {
    let result = TerminologyNormalizer().normalize(
        text: "保留 https://example.com/Takwiisper 和 --takwiisper 以及 /tmp/Takwiisper，不要乱改。",
        importedEntries: [
            TerminologyEntry(
                canonical: "TypeWhisper",
                aliases: ["Type Whisper"],
                caseSensitive: true
            ),
        ],
        hintTerms: []
    )

    #expect(result.text == "保留 https://example.com/Takwiisper 和 --takwiisper 以及 /tmp/Takwiisper，不要乱改。")
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func transcriptionPromptBuilderIncludesDirectUseGuidanceAndHintTerms() {
    let prompt = TranscriptionPromptBuilder().buildPrompt(
        hintTerms: ["budget v2.xlsx", "ChatType"],
        locale: "zh-CN"
    )

    #expect(prompt.contains("输出带自然标点"))
    #expect(prompt.contains("直接粘贴使用"))
    #expect(prompt.contains("budget v2.xlsx"))
    #expect(prompt.contains("ChatType"))
}

@Test
func transcriptionPromptBuilderRequestsSimplifiedChineseByDefault() {
    let prompt = TranscriptionPromptBuilder().buildPrompt(
        hintTerms: [],
        locale: "zh-CN"
    )

    #expect(prompt.contains("简体中文"))
    #expect(prompt.contains("不要输出繁体中文"))
}

@Test
func dictationPipelineRunsTranscribeThenNormalizeWithoutCleanupStage() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "请把 Budget V2.XLSX 发出来，chattype 现在可以用了。",
                metrics: .init(
                    provider: .codexChatGPTBridge,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [
            TerminologyEntry(
                canonical: "TypeWhisper",
                aliases: ["Type Whisper"],
                caseSensitive: true
            ),
        ],
        hintTerms: ["budget v2.xlsx", "ChatType"]
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.rawText == "请把 Budget V2.XLSX 发出来，chattype 现在可以用了。")
    #expect(result.finalText == "请把 budget v2.xlsx 发出来，ChatType 现在可以用了。")
    #expect(result.metrics.normalizationMs >= 0)
    #expect(result.exactReplacementCount == 2)
    #expect(result.fuzzyReplacementCount == 0)
}

@Test
func dictationPipelineReportsExactAndFuzzyReplacementCounts() async throws {
    let pipeline = DictationPipeline(
        transcriber: FakeTranscriber(
            result: TranscriptionResult(
                text: "Takwiisper 和 chattype 都得写对。",
                metrics: .init(
                    provider: .codexChatGPTBridge,
                    audioDurationMs: 2_000,
                    audioBytes: 128_000,
                    authMs: 50,
                    transcribeMs: 400,
                    promptIncluded: false
                )
            )
        ),
        normalizer: TerminologyNormalizer(),
        importedEntries: [
            TerminologyEntry(
                canonical: "TypeWhisper",
                aliases: ["Type Whisper"],
                caseSensitive: true
            ),
        ],
        hintTerms: ["ChatType"]
    )

    let audio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fake-2.wav"),
        durationMs: 2_000
    )

    let result = try await pipeline.prepare(audio: audio)
    #expect(result.finalText == "TypeWhisper 和 ChatType 都得写对。")
    #expect(result.exactReplacementCount == 1)
    #expect(result.fuzzyReplacementCount == 1)
}
