import Foundation

struct TranscriptionPromptBuilder {
    func buildPrompt(
        hintTerms: [String],
        locale: String = Locale.preferredLanguages.first ?? "zh-CN"
    ) -> String {
        let hints = hintTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var lines: [String] = [
            "请将这段语音转成可直接粘贴使用的文本。",
            "输出带自然标点和断句，但不要做二次改写。",
            "保留中英混合表达，保持原意。",
            "不要改动文件名、版本号、路径、URL、邮箱、产品名、命令、参数名。",
            "优先正确写出术语、缩写、品牌词。",
            "只返回最终文本。",
            "Locale: \(locale)",
        ]

        if !hints.isEmpty {
            lines.append("请特别注意这些术语：")
            lines.append(contentsOf: hints.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}
