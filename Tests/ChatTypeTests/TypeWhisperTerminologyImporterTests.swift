import Foundation
import Testing
@testable import ChatType

private func runSQLite(_ databaseURL: URL, sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [databaseURL.path, sql]

    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let errorOutput = String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    #expect(process.terminationStatus == 0, Comment(rawValue: errorOutput))
}

@Test
func importerBuildsDictionaryEntriesFromTypeWhisperDictionary() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("store")

    try runSQLite(
        databaseURL,
        sql: """
        CREATE TABLE ZDICTIONARYENTRY (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            Z_OPT INTEGER,
            ZCASESENSITIVE INTEGER,
            ZISENABLED INTEGER,
            ZUSAGECOUNT INTEGER,
            ZCREATEDAT TIMESTAMP,
            ZENTRYTYPE VARCHAR,
            ZORIGINAL VARCHAR,
            ZREPLACEMENT VARCHAR,
            ZID BLOB
        );
        INSERT INTO ZDICTIONARYENTRY (ZCASESENSITIVE, ZISENABLED, ZUSAGECOUNT, ZCREATEDAT, ZENTRYTYPE, ZORIGINAL, ZREPLACEMENT) VALUES
            (1, 1, 7, '2026-05-07 10:00:00', 'term', 'TypeWhisper', ''),
            (1, 1, 3, '2026-05-07 10:01:00', 'term', 'Type Whisper', 'TypeWhisper'),
            (1, 1, 2, '2026-05-07 10:02:00', 'term', 'Takwiisper', 'TypeWhisper'),
            (1, 1, 1, '2026-05-07 10:03:00', 'term', 'Open AI Compatible', 'OpenAI Compatible'),
            (0, 1, 4, '2026-05-07 10:04:00', 'correction', 'opencloud', 'OpenClaw'),
            (1, 0, 9, '2026-05-07 10:05:00', 'term', 'Disabled Alias', 'TypeWhisper'),
            (1, 1, 1, '2026-05-07 10:06:00', 'note', 'Ignored Note', 'TypeWhisper');
        """
    )

    let result = try TypeWhisperTerminologyImporter().importEntries(from: databaseURL)

    #expect(result.source == databaseURL.path)
    #expect(result.entries.count == 4)

    let typeWhisper = try #require(result.entries.first(where: { $0.original == "TypeWhisper" }))
    #expect(typeWhisper.type == .term)
    #expect(typeWhisper.aliases == ["Takwiisper", "Type Whisper"])
    #expect(typeWhisper.isEnabled == true)
    #expect(typeWhisper.source == "typewhisper-import")

    let openAICompatible = try #require(result.entries.first(where: { $0.original == "OpenAI Compatible" }))
    #expect(openAICompatible.aliases == ["Open AI Compatible"])

    let openClaw = try #require(result.entries.first(where: { $0.type == .correction && $0.original == "opencloud" }))
    #expect(openClaw.replacement == "OpenClaw")
    #expect(openClaw.isEnabled == true)
    #expect(openClaw.usageCount == 4)
}

@Test
func importerReportsMissingDictionaryStore() {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("store")

    #expect(throws: TypeWhisperTerminologyImportError.missingDatabase(databaseURL.path)) {
        try TypeWhisperTerminologyImporter().importEntries(from: databaseURL)
    }
}

@Test
func importerReportsUnreadableSchemaForInvalidDatabase() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("store")
    try Data("not-a-sqlite-db".utf8).write(to: databaseURL)

    #expect(throws: TypeWhisperTerminologyImportError.unreadableSchema(databaseURL.path)) {
        try TypeWhisperTerminologyImporter().importEntries(from: databaseURL)
    }
}

@Test
func importerPreservesDisabledRowsAsDisabledDictionaryEntries() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("store")

    try runSQLite(
        databaseURL,
        sql: """
        CREATE TABLE ZDICTIONARYENTRY (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            Z_OPT INTEGER,
            ZCASESENSITIVE INTEGER,
            ZISENABLED INTEGER,
            ZUSAGECOUNT INTEGER,
            ZCREATEDAT TIMESTAMP,
            ZENTRYTYPE VARCHAR,
            ZORIGINAL VARCHAR,
            ZREPLACEMENT VARCHAR,
            ZID BLOB
        );
        INSERT INTO ZDICTIONARYENTRY (ZCASESENSITIVE, ZISENABLED, ZENTRYTYPE, ZORIGINAL, ZREPLACEMENT) VALUES
            (1, 0, 'term', 'Disabled Alias', 'TypeWhisper');
        """
    )

    let result = try TypeWhisperTerminologyImporter().importEntries(from: databaseURL)
    let disabled = try #require(result.entries.first)
    #expect(disabled.original == "Disabled Alias")
    #expect(disabled.isEnabled == false)
}

@Test
func importerReportsNoValidEntriesWhenOnlyUnsupportedRowsExist() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("store")

    try runSQLite(
        databaseURL,
        sql: """
        CREATE TABLE ZDICTIONARYENTRY (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            Z_OPT INTEGER,
            ZCASESENSITIVE INTEGER,
            ZISENABLED INTEGER,
            ZUSAGECOUNT INTEGER,
            ZCREATEDAT TIMESTAMP,
            ZENTRYTYPE VARCHAR,
            ZORIGINAL VARCHAR,
            ZREPLACEMENT VARCHAR,
            ZID BLOB
        );
        INSERT INTO ZDICTIONARYENTRY (ZCASESENSITIVE, ZISENABLED, ZENTRYTYPE, ZORIGINAL, ZREPLACEMENT) VALUES
            (1, 1, 'note', 'Ignored Note', 'TypeWhisper');
        """
    )

    #expect(throws: TypeWhisperTerminologyImportError.noValidEntries(databaseURL.path)) {
        try TypeWhisperTerminologyImporter().importEntries(from: databaseURL)
    }
}
