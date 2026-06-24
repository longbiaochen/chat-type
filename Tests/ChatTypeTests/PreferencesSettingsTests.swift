import Foundation
import Testing

@Test
func settingsSidebarUsesProcessingBesideHistoryWithoutInlineTranscriptHistory() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ChatType/PreferencesWindowController.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("case processing = \"Processing\""))
    #expect(source.contains("case recovery = \"History\""))
    #expect(!source.contains("case dictation = \"Dictation\""))
    #expect(!source.contains("case polish = \"AI Polish\""))
    #expect(!source.contains("case .polish:"))
    #expect(source.contains("processingWorkflowCard"))
    #expect(source.contains("Configure the recording, ASR, and AI polish steps in the F5 workflow."))
    #expect(source.contains("settingsCard(title: \"AI Polish\")"))
    #expect(!source.contains("Recent Dictation History"))
    #expect(!source.contains("Recent Polish History"))
    #expect(!source.contains("historySection("))
}
