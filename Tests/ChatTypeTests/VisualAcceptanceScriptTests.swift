import Foundation
import Testing

@Test
func visualAcceptanceScriptRunsInstalledChatTypeOverlayDemo() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = root.appendingPathComponent("scripts/visual_acceptance.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("/Applications/ChatType.app"))
    #expect(script.contains("CHATTYPE_OVERLAY_DEMO=1"))
    #expect(script.contains("--args --overlay-demo-state"))
    #expect(script.contains("prepare_visual_acceptance_screen.swift"))
    #expect(script.contains("screencapture"))
    #expect(script.contains("verify_visual_acceptance.swift"))
    #expect(!script.contains("dist/ChatType.app/Contents/MacOS/ChatType"))
}

@Test
func visualAcceptanceVerifierDocumentsRequiredStates() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let verifierURL = root.appendingPathComponent("scripts/verify_visual_acceptance.swift")
    let verifier = try String(contentsOf: verifierURL, encoding: .utf8)

    for state in ["recording", "processing", "result", "error", "retryable-error"] {
        #expect(verifier.contains(state))
    }
}
