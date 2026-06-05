import Foundation

struct RecoveryRecordInput: Sendable {
    let timestamp: Date
    let sourceAudioURL: URL
    let durationMs: Int
    let asrText: String?
    let polishText: String?
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let errorMessage: String?
}

struct RecoveryRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let audioFileName: String
    let audioDurationMs: Int
    let asrText: String?
    let polishText: String?
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let errorMessage: String?

    func audioURL(baseDirectory: URL) -> URL {
        baseDirectory
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent(audioFileName)
    }
}

enum RecoveryHistoryKind: String, CaseIterable, Identifiable, Sendable {
    case audio
    case asr
    case polish

    var id: String { rawValue }
}

enum RecoveryCopyKind: Sendable, Equatable {
    case audioFile
    case text
}

struct RecoveryHistoryPreview: Sendable, Equatable, Identifiable {
    let id: String
    let recordID: UUID
    let kind: RecoveryHistoryKind
    let timestamp: Date
    let text: String
    let copyText: String
    let copyKind: RecoveryCopyKind
    let target: String
    let outcome: String
    let errorMessage: String?
    let audioFileName: String
    let audioDurationMs: Int

    static func recentItems(
        from records: [RecoveryRecord],
        kind: RecoveryHistoryKind,
        limit: Int
    ) -> [RecoveryHistoryPreview] {
        records
            .sorted { $0.timestamp > $1.timestamp }
            .compactMap { record in
                makePreview(from: record, kind: kind)
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func makePreview(
        from record: RecoveryRecord,
        kind: RecoveryHistoryKind
    ) -> RecoveryHistoryPreview? {
        let copyText: String
        let displayText: String
        let copyKind: RecoveryCopyKind

        switch kind {
        case .audio:
            copyText = ""
            copyKind = .audioFile
            displayText = "\(formattedDuration(record.audioDurationMs)) WAV"
        case .asr:
            guard let text = record.asrText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            copyText = text
            copyKind = .text
            displayText = collapsedPreview(text)
        case .polish:
            guard let text = record.polishText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            copyText = text
            copyKind = .text
            displayText = collapsedPreview(text)
        }

        return RecoveryHistoryPreview(
            id: "\(kind.rawValue)-\(record.id.uuidString)",
            recordID: record.id,
            kind: kind,
            timestamp: record.timestamp,
            text: displayText,
            copyText: copyText,
            copyKind: copyKind,
            target: record.appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? record.appName ?? "Unknown target"
                : "Unknown target",
            outcome: record.outcome,
            errorMessage: record.errorMessage,
            audioFileName: record.audioFileName,
            audioDurationMs: record.audioDurationMs
        )
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

    private static func formattedDuration(_ durationMs: Int) -> String {
        let seconds = max(0, durationMs) / 1_000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

protocol RecoveryRecording: Sendable {
    var directoryURL: URL { get }
    func record(_ input: RecoveryRecordInput) throws
    func loadRecent(limit: Int) throws -> [RecoveryRecord]
}

final class RecoveryStore: RecoveryRecording, @unchecked Sendable {
    private let fileManager: FileManager
    let directoryURL: URL
    private let lock = NSLock()
    private let retainedLimit: Int

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        retainedLimit: Int = 10
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ChatType/Recovery", isDirectory: true)
        self.retainedLimit = retainedLimit
    }

    func record(_ input: RecoveryRecordInput) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)
        var records = try loadRecentUnlocked(limit: retainedLimit)
        let id = UUID()
        let audioFileName = "\(id.uuidString).wav"
        let destinationURL = audioDirectoryURL.appendingPathComponent(audioFileName)
        try fileManager.copyItem(at: input.sourceAudioURL, to: destinationURL)
        records.append(
            RecoveryRecord(
                id: id,
                timestamp: input.timestamp,
                audioFileName: audioFileName,
                audioDurationMs: input.durationMs,
                asrText: input.asrText,
                polishText: input.polishText,
                appName: input.appName,
                appBundleIdentifier: input.appBundleIdentifier,
                outcome: input.outcome,
                errorMessage: input.errorMessage
            )
        )
        records = Array(records.sorted { $0.timestamp < $1.timestamp }.suffix(retainedLimit))
        try rewrite(records)
    }

    func loadRecent(limit: Int = 10) throws -> [RecoveryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try loadRecentUnlocked(limit: limit)
    }

    private func loadRecentUnlocked(limit: Int) throws -> [RecoveryRecord] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let contents = try String(contentsOf: indexURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return contents
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(RecoveryRecord.self, from: Data(line.utf8))
            }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(max(0, limit))
            .map { $0 }
    }

    private func rewrite(_ records: [RecoveryRecord]) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try records.reduce(into: Data()) { partial, record in
            partial.append(try encoder.encode(record))
            partial.append(0x0A)
        }
        try data.write(to: indexURL, options: [.atomic])

        let retainedFileNames = Set(records.map(\.audioFileName))
        let existingAudioFiles = (try? fileManager.contentsOfDirectory(at: audioDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for audioFile in existingAudioFiles where !retainedFileNames.contains(audioFile.lastPathComponent) {
            try? fileManager.removeItem(at: audioFile)
        }
    }

    private var indexURL: URL {
        directoryURL.appendingPathComponent("recovery-history.jsonl")
    }

    private var audioDirectoryURL: URL {
        directoryURL.appendingPathComponent("Audio", isDirectory: true)
    }
}
