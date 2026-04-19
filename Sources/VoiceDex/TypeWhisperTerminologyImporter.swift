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

    private func fetchRows(from databaseURL: URL) throws -> [(original: String, replacement: String, caseSensitive: Bool)] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw TypeWhisperTerminologyImportError.unreadableSchema(databaseURL.path)
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT ZORIGINAL, COALESCE(ZREPLACEMENT, ''), ZCASESENSITIVE
        FROM ZDICTIONARYENTRY
        WHERE ZISENABLED = 1
          AND ZENTRYTYPE = 'term'
          AND TRIM(COALESCE(ZORIGINAL, '')) != ''
        ORDER BY Z_PK ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw TypeWhisperTerminologyImportError.unreadableSchema(databaseURL.path)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [(original: String, replacement: String, caseSensitive: Bool)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let original = String(cString: sqlite3_column_text(statement, 0))
            let replacement = String(cString: sqlite3_column_text(statement, 1))
            let caseSensitive = sqlite3_column_int(statement, 2) != 0
            rows.append((original, replacement, caseSensitive))
        }

        return rows
    }

    private func merge(
        rows: [(original: String, replacement: String, caseSensitive: Bool)]
    ) -> [TerminologyEntry] {
        struct PartialEntry {
            var canonical: String
            var aliases: [String] = []
            var aliasKeys: Set<String> = []
            var caseSensitive: Bool

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

        for row in rows {
            let original = row.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = row.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else {
                continue
            }

            let canonical = replacement.isEmpty ? original : replacement
            let key = canonical.lowercased()

            if merged[key] == nil {
                merged[key] = PartialEntry(
                    canonical: canonical,
                    caseSensitive: row.caseSensitive
                )
            }

            if !replacement.isEmpty {
                merged[key]?.addAlias(original)
            }
        }

        return merged.values
            .map { partial in
                TerminologyEntry(
                    canonical: partial.canonical,
                    aliases: partial.aliases.sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    },
                    caseSensitive: partial.caseSensitive
                )
            }
            .sorted {
                $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending
            }
    }
}
