import Foundation
import SQLite3

struct TypeWhisperTerminologyImportResult: Sendable, Equatable {
    let entries: [TerminologyEntry]
    let source: String
    let importedAt: String
}

enum TypeWhisperTerminologyImportError: LocalizedError, Equatable {
    case missingDatabase(String)
    case unreadableSchema(String)
    case noValidEntries(String)

    var errorDescription: String? {
        switch self {
        case .missingDatabase(let path):
            return "TypeWhisper dictionary.store not found at \(path)."
        case .unreadableSchema(let path):
            return "Unable to read the TypeWhisper dictionary schema at \(path)."
        case .noValidEntries(let path):
            return "No enabled term entries were found in \(path)."
        }
    }
}

struct TypeWhisperTerminologyImporter {
    private let fileManager: FileManager
    private let iso8601Formatter: ISO8601DateFormatter

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.iso8601Formatter = ISO8601DateFormatter()
    }

    func importEntries(from databaseURL: URL? = nil) throws -> TypeWhisperTerminologyImportResult {
        let sourceURL = databaseURL ?? defaultDictionaryURL()
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw TypeWhisperTerminologyImportError.missingDatabase(sourceURL.path)
        }

        let rows = try fetchRows(from: sourceURL)
        let entries = merge(rows: rows)
        guard !entries.isEmpty else {
            throw TypeWhisperTerminologyImportError.noValidEntries(sourceURL.path)
        }

        return TypeWhisperTerminologyImportResult(
            entries: entries,
            source: sourceURL.path,
            importedAt: iso8601Formatter.string(from: Date())
        )
    }

    private func defaultDictionaryURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TypeWhisper", isDirectory: true)
            .appendingPathComponent("dictionary.store")
    }

    private struct TypeWhisperRow {
        let type: TerminologyEntryType
        let original: String
        let replacement: String
        let isEnabled: Bool
        let usageCount: Int
        let createdAt: String?
    }

    private func fetchRows(from databaseURL: URL) throws -> [TypeWhisperRow] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw TypeWhisperTerminologyImportError.unreadableSchema(databaseURL.path)
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT ZENTRYTYPE, ZORIGINAL, COALESCE(ZREPLACEMENT, ''), ZCASESENSITIVE, ZISENABLED, COALESCE(ZUSAGECOUNT, 0), ZCREATEDAT
        FROM ZDICTIONARYENTRY
        WHERE ZENTRYTYPE IN ('term', 'correction')
          AND TRIM(COALESCE(ZORIGINAL, '')) != ''
        ORDER BY Z_PK ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw TypeWhisperTerminologyImportError.unreadableSchema(databaseURL.path)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [TypeWhisperRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rawType = String(cString: sqlite3_column_text(statement, 0))
            guard let type = TerminologyEntryType(rawValue: rawType) else {
                continue
            }

            let original = String(cString: sqlite3_column_text(statement, 1))
            let replacement = String(cString: sqlite3_column_text(statement, 2))
            let isEnabled = sqlite3_column_int(statement, 4) != 0
            let usageCount = Int(sqlite3_column_int(statement, 5))
            let createdAt = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            rows.append(
                TypeWhisperRow(
                    type: type,
                    original: original,
                    replacement: replacement,
                    isEnabled: isEnabled,
                    usageCount: usageCount,
                    createdAt: createdAt
                )
            )
        }

        return rows
    }

    private func merge(
        rows: [TypeWhisperRow]
    ) -> [TerminologyEntry] {
        struct PartialEntry {
            var canonical: String
            var aliases: [String] = []
            var aliasKeys: Set<String> = []
            var isEnabled: Bool
            var usageCount: Int
            var createdAt: String

            mutating func addAlias(_ alias: String) {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return
                }

                let aliasKey = trimmed.lowercased()
                guard aliasKey != canonical.lowercased(), !aliasKeys.contains(aliasKey) else {
                    return
                }

                aliasKeys.insert(aliasKey)
                aliases.append(trimmed)
            }
        }

        var merged: [String: PartialEntry] = [:]
        var corrections: [TerminologyEntry] = []

        for row in rows {
            let original = row.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = row.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else {
                continue
            }

            if row.type == .correction {
                corrections.append(
                    TerminologyEntry(
                        type: .correction,
                        original: original,
                        replacement: replacement,
                        aliases: [],
                        isEnabled: row.isEnabled,
                        source: "typewhisper-import",
                        usageCount: row.usageCount,
                        createdAt: normalizedCreatedAt(row.createdAt)
                    )
                )
                continue
            }

            if !row.isEnabled {
                corrections.append(
                    TerminologyEntry(
                        type: .term,
                        original: original,
                        replacement: nil,
                        aliases: [],
                        isEnabled: false,
                        source: "typewhisper-import",
                        usageCount: row.usageCount,
                        createdAt: normalizedCreatedAt(row.createdAt)
                    )
                )
                continue
            }

            let canonical = replacement.isEmpty ? original : replacement
            let key = canonical.lowercased()

            if merged[key] == nil {
                merged[key] = PartialEntry(
                    canonical: canonical,
                    isEnabled: row.isEnabled,
                    usageCount: row.usageCount,
                    createdAt: normalizedCreatedAt(row.createdAt)
                )
            }

            if !replacement.isEmpty {
                merged[key]?.addAlias(original)
            }
        }

        return (
            merged.values
            .map { partial in
                TerminologyEntry(
                    type: .term,
                    original: partial.canonical,
                    replacement: nil,
                    aliases: partial.aliases.sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    },
                    isEnabled: partial.isEnabled,
                    source: "typewhisper-import",
                    usageCount: partial.usageCount,
                    createdAt: partial.createdAt
                )
            }
            + corrections
        )
            .sorted {
                $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending
            }
    }

    private func normalizedCreatedAt(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return iso8601Formatter.string(from: Date())
        }
        return value
    }
}
