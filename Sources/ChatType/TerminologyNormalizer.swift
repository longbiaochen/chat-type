import Foundation

struct NormalizationResult: Sendable, Equatable {
    let text: String
    let applied: Bool
    let exactReplacementCount: Int
    let fuzzyReplacementCount: Int
}

private struct ExactRule {
    let canonical: String
    let regex: NSRegularExpression
    let sortKey: Int
}

private struct FuzzyRule {
    let canonical: String
    let referenceSkeletons: [String]
}

private struct FuzzyCandidate {
    let canonical: String
    let distance: Int
    let similarity: Double
}

private struct FuzzyPassResult {
    let text: String
    let replacementCount: Int
}

struct TerminologyNormalizer: TranscriptNormalizing {
    func normalize(
        text: String,
        importedEntries: [TerminologyEntry],
        hintTerms: [String]
    ) -> NormalizationResult {
        let artifactStrippedText = stripKnownTrailingArtifacts(from: text)
        let simplifiedText = simplifiedChineseText(from: artifactStrippedText)
        var output = simplifiedText
        var applied = artifactStrippedText != text || simplifiedText != artifactStrippedText

        let exactPass = applyExactRules(
            to: output,
            rules: exactRules(
                importedEntries: importedEntries,
                hintTerms: hintTerms
            )
        )
        output = exactPass.text
        applied = applied || exactPass.replacementCount > 0

        let fuzzyPass = applyFuzzyRules(
            to: output,
            rules: fuzzyRules(from: importedEntries)
        )
        output = fuzzyPass.text
        applied = applied || fuzzyPass.replacementCount > 0

        return NormalizationResult(
            text: output,
            applied: applied,
            exactReplacementCount: exactPass.replacementCount,
            fuzzyReplacementCount: fuzzyPass.replacementCount
        )
    }

    private func applyExactRules(
        to text: String,
        rules: [ExactRule]
    ) -> (text: String, replacementCount: Int) {
        var output = text
        var replacementCount = 0

        for rule in rules.sorted(by: { $0.sortKey > $1.sortKey }) {
            let matches = rule.regex.matches(
                in: output,
                options: [],
                range: NSRange(output.startIndex..., in: output)
            )

            for match in matches.reversed() {
                guard let range = Range(match.range, in: output) else {
                    continue
                }

                let matchedText = String(output[range])
                guard matchedText != rule.canonical else {
                    continue
                }

                output.replaceSubrange(range, with: rule.canonical)
                replacementCount += 1
            }
        }

        return (output, replacementCount)
    }

    private func applyFuzzyRules(
        to text: String,
        rules: [FuzzyRule]
    ) -> FuzzyPassResult {
        guard !rules.isEmpty else {
            return FuzzyPassResult(text: text, replacementCount: 0)
        }

        let protectedRanges = protectedLiteralRanges(in: text)
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?<![A-Za-z0-9])([A-Za-z0-9]+(?:[ ._-]+[A-Za-z0-9]+){0,2})(?![A-Za-z0-9])"#,
                options: []
            )
        else {
            return FuzzyPassResult(text: text, replacementCount: 0)
        }

        let matches = regex.matches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..., in: text)
        )

        var output = text
        var replacementCount = 0

        for match in matches.reversed() {
            let candidateRange = match.range(at: 1)
            guard
                candidateRange.location != NSNotFound,
                !protectedRanges.contains(where: { NSIntersectionRange($0, candidateRange).length > 0 }),
                let range = Range(candidateRange, in: output)
            else {
                continue
            }

            let candidate = String(output[range])
            guard let winner = bestFuzzyMatch(for: candidate, rules: rules) else {
                continue
            }
            guard candidate != winner.canonical else {
                continue
            }

            output.replaceSubrange(range, with: winner.canonical)
            replacementCount += 1
        }

        return FuzzyPassResult(text: output, replacementCount: replacementCount)
    }

    private func bestFuzzyMatch(
        for candidate: String,
        rules: [FuzzyRule]
    ) -> FuzzyCandidate? {
        let candidateSkeleton = collapsedLatinSkeleton(for: candidate)
        guard candidateSkeleton.count >= 5 else {
            return nil
        }

        var bestCandidates: [FuzzyCandidate] = []

        for rule in rules {
            var bestForCanonical: FuzzyCandidate?

            for reference in rule.referenceSkeletons {
                let distance = damerauLevenshteinDistance(
                    Array(candidateSkeleton),
                    Array(reference)
                )
                let maxLength = max(candidateSkeleton.count, reference.count)
                guard maxLength > 0 else {
                    continue
                }

                let similarity = 1 - (Double(distance) / Double(maxLength))
                guard isAcceptedFuzzyMatch(
                    candidateSkeleton: candidateSkeleton,
                    referenceSkeleton: reference,
                    distance: distance,
                    similarity: similarity
                ) else {
                    continue
                }

                let candidateScore = FuzzyCandidate(
                    canonical: rule.canonical,
                    distance: distance,
                    similarity: similarity
                )

                if let currentBest = bestForCanonical {
                    if isBetter(candidateScore, than: currentBest) {
                        bestForCanonical = candidateScore
                    }
                } else {
                    bestForCanonical = candidateScore
                }
            }

            if let bestForCanonical {
                bestCandidates.append(bestForCanonical)
            }
        }

        let ordered = bestCandidates.sorted(by: isBetter(_:than:))
        guard let first = ordered.first else {
            return nil
        }

        if let second = ordered.dropFirst().first, !hasClearWinner(first, over: second) {
            return nil
        }

        return first
    }

    private func isAcceptedFuzzyMatch(
        candidateSkeleton: String,
        referenceSkeleton: String,
        distance: Int,
        similarity: Double
    ) -> Bool {
        switch candidateSkeleton.count {
        case 0..<5:
            return false
        case 5...8:
            if similarity >= 0.72 {
                return distance <= 2
            }
        default:
            if similarity >= 0.72 {
                return distance <= 3
            }
        }

        return distance <= 4
            && similarity >= 0.60
            && candidateSkeleton.first == referenceSkeleton.first
            && commonSuffixLength(candidateSkeleton, referenceSkeleton) >= 5
    }

    private func isBetter(_ lhs: FuzzyCandidate, than rhs: FuzzyCandidate) -> Bool {
        if lhs.similarity != rhs.similarity {
            return lhs.similarity > rhs.similarity
        }
        if lhs.distance != rhs.distance {
            return lhs.distance < rhs.distance
        }
        return lhs.canonical.localizedCaseInsensitiveCompare(rhs.canonical) == .orderedAscending
    }

    private func hasClearWinner(
        _ first: FuzzyCandidate,
        over second: FuzzyCandidate
    ) -> Bool {
        if first.distance + 1 < second.distance {
            return true
        }

        return first.similarity - second.similarity >= 0.08
    }

    private func exactRules(
        importedEntries: [TerminologyEntry],
        hintTerms: [String]
    ) -> [ExactRule] {
        var rules: [ExactRule] = []

        for entry in importedEntries {
            rules.append(contentsOf: exactRules(for: entry))
        }

        for term in normalizedTerms(from: hintTerms) {
            if let regex = try? NSRegularExpression(
                pattern: exactPattern(for: term),
                options: [.caseInsensitive]
            ) {
                rules.append(
                    ExactRule(
                        canonical: term,
                        regex: regex,
                        sortKey: collapsedLatinSkeleton(for: term).count
                    )
                )
            }
        }

        return rules
    }

    private func exactRules(for entry: TerminologyEntry) -> [ExactRule] {
        var seen = Set<String>()
        var rules: [ExactRule] = []

        for term in normalizedTerms(from: [entry.canonical] + entry.aliases) {
            let key = term.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)

            guard let regex = try? NSRegularExpression(
                pattern: exactPattern(for: term),
                options: [.caseInsensitive]
            ) else {
                continue
            }

            rules.append(
                ExactRule(
                    canonical: entry.canonical,
                    regex: regex,
                    sortKey: collapsedLatinSkeleton(for: term).count
                )
            )
        }

        return rules
    }

    private func fuzzyRules(from entries: [TerminologyEntry]) -> [FuzzyRule] {
        entries.compactMap { entry in
            let references = normalizedTerms(from: [entry.canonical] + entry.aliases)
                .filter { containsLatinLetters($0) }
                .filter { !shouldSkipFuzzyReference($0) }
                .map(collapsedLatinSkeleton(for:))
                .filter { !$0.isEmpty }

            guard !references.isEmpty else {
                return nil
            }

            return FuzzyRule(
                canonical: entry.canonical,
                referenceSkeletons: Array(Set(references)).sorted()
            )
        }
    }

    private func shouldSkipFuzzyReference(_ term: String) -> Bool {
        let skeleton = collapsedLatinSkeleton(for: term)
        guard !skeleton.isEmpty else {
            return true
        }

        if skeleton.count < 5, isPureLowercaseLatin(term) {
            return true
        }

        return false
    }

    private func exactPattern(for term: String) -> String {
        guard containsLatinLetters(term) else {
            return flexibleLiteralPattern(for: term)
        }

        let tokens = term
            .split(whereSeparator: { $0.isWhitespace || "._-".contains($0) })
            .map(String.init)
            .filter { !$0.isEmpty }

        let corePattern: String
        if tokens.count > 1 {
            corePattern = tokens
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: #"(?:[\s._-]+)"#)
        } else {
            corePattern = NSRegularExpression.escapedPattern(for: term)
        }

        return #"(?<![A-Za-z0-9])\#(corePattern)(?![A-Za-z0-9])"#
    }

    private func flexibleLiteralPattern(for term: String) -> String {
        var pattern = ""
        for character in term {
            if character.isWhitespace {
                pattern += #"\s+"#
            } else {
                pattern += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return pattern
    }

    private func protectedLiteralRanges(in text: String) -> [NSRange] {
        let patterns = [
            #"https?://\S+"#,
            #"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b"#,
            #"(?:~|/)[^\s]+"#,
            #"(?<!\S)--?[A-Za-z0-9][A-Za-z0-9-]*"#,
            #"\bv?\d+(?:\.\d+){1,}\b"#,
        ]

        let fullRange = NSRange(text.startIndex..., in: text)
        return patterns.flatMap { pattern -> [NSRange] in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return []
            }
            return regex.matches(in: text, options: [], range: fullRange).map(\.range)
        }
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

    private func stripKnownTrailingArtifacts(from text: String) -> String {
        let trailingBoundaryNoise = "[\\s\u{200B}\u{200C}\u{200D}\u{FEFF}\u{2060}]*"
        let patterns = [
            "\\s*Ask Codex anything\\. @ to use plugins or use files\(trailingBoundaryNoise)$",
            "\\s*Ask Codex anything(?:\\.\\s*@ to use plugins or use files|,\\s*@ add files,\\s*/ for commands,\\s*\\$ for skills)?\(trailingBoundaryNoise)$",
            "\\s*Ask for follow-up changes(?:\\s+or(?:\\s+use)?\\s+@\\s+to\\s+tag\\s+an\\s+agent)?\(trailingBoundaryNoise)$",
        ]

        var output = text
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let fullRange = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: fullRange,
                withTemplate: ""
            )
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTerms(from terms: [String]) -> [String] {
        terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func containsLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.isASCII && CharacterSet.letters.contains(scalar)
        }
    }

    private func collapsedLatinSkeleton(for text: String) -> String {
        let filteredScalars = text.lowercased().unicodeScalars.filter { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
        }
        return String(String.UnicodeScalarView(filteredScalars))
    }

    private func isPureLowercaseLatin(_ text: String) -> Bool {
        let latinLetters = text.unicodeScalars.filter {
            $0.isASCII && CharacterSet.letters.contains($0)
        }
        guard !latinLetters.isEmpty else {
            return false
        }

        return latinLetters.allSatisfy { CharacterSet.lowercaseLetters.contains($0) }
    }

    private func damerauLevenshteinDistance(
        _ lhs: [Character],
        _ rhs: [Character]
    ) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var matrix = Array(
            repeating: Array(repeating: 0, count: rhs.count + 1),
            count: lhs.count + 1
        )

        for i in 0...lhs.count {
            matrix[i][0] = i
        }
        for j in 0...rhs.count {
            matrix[0][j] = j
        }

        for i in 1...lhs.count {
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )

                if i > 1,
                   j > 1,
                   lhs[i - 1] == rhs[j - 2],
                   lhs[i - 2] == rhs[j - 1] {
                    matrix[i][j] = min(matrix[i][j], matrix[i - 2][j - 2] + 1)
                }
            }
        }

        return matrix[lhs.count][rhs.count]
    }

    private func commonSuffixLength(
        _ lhs: String,
        _ rhs: String
    ) -> Int {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        var count = 0
        var lhsIndex = lhsCharacters.count - 1
        var rhsIndex = rhsCharacters.count - 1

        while lhsIndex >= 0,
              rhsIndex >= 0,
              lhsCharacters[lhsIndex] == rhsCharacters[rhsIndex] {
            count += 1
            lhsIndex -= 1
            rhsIndex -= 1
        }

        return count
    }
}
