import Foundation

struct TranscriptionHistoryRecord: Codable, Sendable, Equatable {
    let timestamp: Date
    let rawText: String?
    let finalText: String
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let textPolishProvider: String?

    init(
        timestamp: Date,
        rawText: String? = nil,
        finalText: String,
        appName: String?,
        appBundleIdentifier: String?,
        outcome: String,
        textPolishProvider: String? = nil
    ) {
        self.timestamp = timestamp
        self.rawText = rawText
        self.finalText = finalText
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.outcome = outcome
        self.textPolishProvider = textPolishProvider
    }
}

enum TranscriptionHistoryTextSource: Sendable {
    case dictation
    case polish
}

struct TranscriptionHistoryPreview: Sendable, Equatable, Identifiable {
    let id: String
    let timestamp: Date
    let text: String
    let copyText: String
    let target: String
    let outcome: String
    let sourceLabel: String

    static func recentItems(
        from records: [TranscriptionHistoryRecord],
        limit: Int
    ) -> [TranscriptionHistoryPreview] {
        records
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(0, limit))
            .map { record in
                let copyText = record.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                return TranscriptionHistoryPreview(
                    id: "final-\(record.timestamp.timeIntervalSince1970)-\(record.outcome)-\(copyText.hashValue)",
                    timestamp: record.timestamp,
                    text: collapsedPreview(copyText),
                    copyText: copyText,
                    target: record.appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? record.appName ?? "Unknown target"
                        : "Unknown target",
                    outcome: record.outcome,
                    sourceLabel: record.textPolishProvider ?? "Final text"
                )
            }
    }

    static func recentItems(
        from records: [TranscriptionHistoryRecord],
        limit: Int,
        textSource: TranscriptionHistoryTextSource
    ) -> [TranscriptionHistoryPreview] {
        records
            .sorted { $0.timestamp > $1.timestamp }
            .filter { record in
                switch textSource {
                case .dictation:
                    return selectedText(from: record, textSource: textSource).isEmpty == false
                case .polish:
                    return selectedText(from: record, textSource: textSource).isEmpty == false
                }
            }
            .prefix(max(0, limit))
            .map { record in
                let copyText = selectedText(from: record, textSource: textSource)
                return TranscriptionHistoryPreview(
                    id: "\(textSource)-\(record.timestamp.timeIntervalSince1970)-\(record.outcome)-\(copyText.hashValue)",
                    timestamp: record.timestamp,
                    text: collapsedPreview(copyText),
                    copyText: copyText,
                    target: record.appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? record.appName ?? "Unknown target"
                        : "Unknown target",
                    outcome: record.outcome,
                    sourceLabel: sourceLabel(for: record, textSource: textSource)
                )
            }
    }

    private static func selectedText(
        from record: TranscriptionHistoryRecord,
        textSource: TranscriptionHistoryTextSource
    ) -> String {
        switch textSource {
        case .dictation:
            return (record.rawText ?? record.finalText).trimmingCharacters(in: .whitespacesAndNewlines)
        case .polish:
            return record.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func sourceLabel(
        for record: TranscriptionHistoryRecord,
        textSource: TranscriptionHistoryTextSource
    ) -> String {
        switch textSource {
        case .dictation:
            return "Direct ASR"
        case .polish:
            return record.textPolishProvider ?? "AI Polish"
        }
    }

    private static func collapsedPreview(_ text: String, maxCharacters: Int = 120) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxCharacters else {
            return collapsed
        }

        return String(collapsed.prefix(maxCharacters)) + "..."
    }
}

protocol TranscriptionHistoryRecording: Sendable {
    func record(_ record: TranscriptionHistoryRecord) throws
    func loadRecent(limit: Int) throws -> [TranscriptionHistoryRecord]
}

final class TranscriptionHistoryRecorder: TranscriptionHistoryRecording, @unchecked Sendable {
    private let fileManager: FileManager
    let directoryURL: URL
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ChatType", isDirectory: true)
    }

    func record(_ record: TranscriptionHistoryRecord) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let dataURL = historyURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(record) + Data([0x0A])

        if fileManager.fileExists(atPath: dataURL.path) {
            let handle = try FileHandle(forWritingTo: dataURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: dataURL, options: [.atomic])
        }
    }

    func loadRecent(limit: Int = 200) throws -> [TranscriptionHistoryRecord] {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }

        let contents = try String(contentsOf: historyURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = contents
            .split(separator: "\n")
            .suffix(max(0, limit))
            .compactMap { line -> TranscriptionHistoryRecord? in
                try? decoder.decode(TranscriptionHistoryRecord.self, from: Data(line.utf8))
            }
        return Array(records)
    }

    private var historyURL: URL {
        directoryURL.appendingPathComponent("transcription-history.jsonl")
    }
}

struct TerminologyLearner {
    func suggestions(
        from records: [TranscriptionHistoryRecord],
        existingEntries: [TerminologyEntry],
        minimumCount: Int = 3
    ) -> [TerminologyEntry] {
        let existingKeys = Set(existingEntries.map { normalizedKey($0.original) })
        var counts: [String: Int] = [:]
        var displayByKey: [String: String] = [:]

        for record in records {
            for candidate in candidates(from: record.finalText) {
                let key = normalizedKey(candidate)
                guard !existingKeys.contains(key) else {
                    continue
                }
                counts[key, default: 0] += 1
                displayByKey[key] = displayByKey[key] ?? candidate
            }
        }

        return counts
            .filter { $0.value >= minimumCount }
            .compactMap { key, count -> TerminologyEntry? in
                guard let display = displayByKey[key] else {
                    return nil
                }
                return TerminologyEntry(
                    type: .suggestion,
                    original: display,
                    replacement: nil,
                    aliases: [],
                    isEnabled: false,
                    source: "auto-suggestion",
                    usageCount: count,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
            }
            .sorted {
                if $0.usageCount != $1.usageCount {
                    return $0.usageCount > $1.usageCount
                }
                return $0.original.localizedCaseInsensitiveCompare($1.original) == .orderedAscending
            }
    }

    private func candidates(from text: String) -> [String] {
        let protectedRanges = protectedLiteralRanges(in: text)
        let pattern = #"\b[A-Za-z][A-Za-z0-9]*(?:[-_][A-Za-z0-9]+){0,3}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match -> String? in
                guard !protectedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      let range = Range(match.range, in: text)
                else {
                    return nil
                }
                let candidate = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                return isTechnicalCandidate(candidate) ? candidate : nil
            }
    }

    private func protectedLiteralRanges(in text: String) -> [NSRange] {
        let patterns = [
            #"https?://\S+"#,
            #"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b"#,
            #"(?:~|/)[^\s]+"#,
        ]
        let fullRange = NSRange(text.startIndex..., in: text)
        return patterns.flatMap { pattern -> [NSRange] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return []
            }
            return regex.matches(in: text, range: fullRange).map(\.range)
        }
    }

    private func isTechnicalCandidate(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else {
            return false
        }

        let lower = compact.lowercased()
        let stopWords: Set<String> = [
            "and", "the", "for", "with", "from", "this", "that", "then", "have", "will",
            "mail", "team", "meeting", "review", "test", "file", "text", "email",
        ]
        guard !stopWords.contains(lower) else {
            return false
        }

        let scalars = Array(compact.unicodeScalars)
        let hasUppercase = scalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        let hasLowercase = scalars.contains { CharacterSet.lowercaseLetters.contains($0) }
        let hasDigit = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        let hasSeparator = text.contains("-") || text.contains("_") || text.contains(" ")
        let isAllCaps = hasUppercase && !hasLowercase
        let isCamelOrPascal = hasUppercase && hasLowercase

        return isAllCaps || isCamelOrPascal || hasDigit || hasSeparator
    }

    private func normalizedKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
