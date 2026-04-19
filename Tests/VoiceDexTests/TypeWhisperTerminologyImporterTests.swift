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
func importerBuildsCanonicalEntriesFromTypeWhisperDictionary() throws {
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
            (1, 1, 'term', 'TypeWhisper', ''),
            (1, 1, 'term', 'Type Whisper', 'TypeWhisper'),
            (1, 1, 'term', 'Takwiisper', 'TypeWhisper'),
            (1, 1, 'term', 'Open AI Compatible', 'OpenAI Compatible'),
            (1, 0, 'term', 'Disabled Alias', 'TypeWhisper'),
            (1, 1, 'note', 'Ignored Note', 'TypeWhisper');
        """
    )

    let result = try TypeWhisperTerminologyImporter().importEntries(from: databaseURL)

    #expect(result.source == databaseURL.path)
    #expect(result.entries.count == 2)

    let typeWhisper = try #require(result.entries.first(where: { $0.canonical == "TypeWhisper" }))
    #expect(typeWhisper.aliases == ["Takwiisper", "Type Whisper"])
    #expect(typeWhisper.caseSensitive == true)
    #expect(typeWhisper.source == "typewhisper-import")

    let openAICompatible = try #require(result.entries.first(where: { $0.canonical == "OpenAI Compatible" }))
    #expect(openAICompatible.aliases == ["Open AI Compatible"])
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
func importerReportsNoValidEntriesWhenOnlyDisabledRowsExist() throws {
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

    #expect(throws: TypeWhisperTerminologyImportError.noValidEntries(databaseURL.path)) {
        try TypeWhisperTerminologyImporter().importEntries(from: databaseURL)
    }
}
