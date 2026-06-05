import Foundation
import Testing

@Test
func settingsSidebarCombinesDictationAndPolishBesideHistory() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ChatType/PreferencesWindowController.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("case dictation = \"Dictation\""))
    #expect(source.contains("case recovery = \"History\""))
    #expect(!source.contains("case polish = \"AI Polish\""))
    #expect(!source.contains("case .polish:"))
    #expect(source.contains("dictationWorkflowCard"))
    #expect(source.contains("Configure recording, ASR, and AI polish for the F5 workflow."))
    #expect(source.contains("settingsCard(title: \"AI Polish\")"))
}
