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
        hintTerms: ["budget v2.xlsx", "review", "ChatType"]
    )

    #expect(result.text.contains("budget v2.xlsx"))
    #expect(result.text.contains("review"))
    #expect(result.text.contains("ChatType"))
    #expect(result.applied == true)
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
}
