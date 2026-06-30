import Foundation
import Testing
@testable import ChatType

@Test
func terminologyTextImporterExtractsPlainTextTerms() throws {
    let text = """
    # ChatType terms
    shadowd
    ChatType

    TypeWhisper
    """

    let result = try TerminologyTextImporter().importEntries(
        from: Data(text.utf8),
        sourceName: "terms.txt"
    )

    #expect(result.source == "terms.txt")
    #expect(result.entries.map(\.original) == ["shadowd", "ChatType", "TypeWhisper"])
    #expect(result.entries.allSatisfy { $0.type == .term && $0.isEnabled && $0.source == "terms.txt" })
}

@Test
func terminologyTextImporterExtractsFirstCsvColumnTerms() throws {
    let text = """
    term,notes
    shadowd,daemon name
    ChatType,app
    "OpenAI Compatible",provider
    """

    let result = try TerminologyTextImporter().importEntries(
        from: Data(text.utf8),
        sourceName: "terms.csv"
    )

    #expect(result.entries.map(\.original) == ["shadowd", "ChatType", "OpenAI Compatible"])
}

@Test
func terminologyTextImporterRejectsEmptyDictionary() {
    #expect(throws: TerminologyTextImportError.noValidEntries("empty.txt")) {
        try TerminologyTextImporter().importEntries(
            from: Data("# only comments\n\n".utf8),
            sourceName: "empty.txt"
        )
    }
}
