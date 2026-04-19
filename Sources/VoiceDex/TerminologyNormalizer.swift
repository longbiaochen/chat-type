import Foundation

struct NormalizationResult: Sendable, Equatable {
    let text: String
    let applied: Bool
}

struct TerminologyNormalizer: TranscriptNormalizing {
    func normalize(text: String, hintTerms: [String]) -> NormalizationResult {
        let simplifiedText = simplifiedChineseText(from: text)
        var output = simplifiedText
        var applied = simplifiedText != text

        for term in normalizedHintTerms(from: hintTerms) {
            let updated = replacingOccurrences(
                of: term,
                in: output
            )
            if updated != output {
                applied = true
                output = updated
            }
        }

        return NormalizationResult(text: output, applied: applied)
    }

    private func simplifiedChineseText(from text: String) -> String {
        let mutableText = NSMutableString(string: text)
        let didTransform = CFStringTransform(
            mutableText,
            nil,
            "Traditional-Simplified" as CFString,
            false
        )

        guard didTransform else {
            return text
        }

        return mutableText as String
    }

    private func normalizedHintTerms(from hintTerms: [String]) -> [String] {
        hintTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func replacingOccurrences(of term: String, in text: String) -> String {
        let pattern = flexiblePattern(for: term)
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: term
        )
    }

    private func flexiblePattern(for term: String) -> String {
        var pattern = ""
        for character in term {
            if character.isWhitespace {
                pattern += "\\s+"
            } else {
                pattern += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return pattern
    }
}
