import Foundation
import Testing
@testable import ChatType

@Test
func accessibilityRepairGuidanceFlagsAdHocBuilds() {
    let guidance = AccessibilityPermission.repairGuidance(
        appName: "ChatType",
        signatureState: .adHocOrUnsigned,
        bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/chat-type/dist/ChatType.app")
    )

    #expect(guidance.detail?.contains("ad-hoc") == true)
    #expect(guidance.detail?.contains("Apple Development") == true)
}

@Test
func accessibilityRepairGuidanceIncludesManualAddPathOutsideApplications() {
    let guidance = AccessibilityPermission.repairGuidance(
        appName: "ChatType",
        signatureState: .stable(teamIdentifier: "TEAM123"),
        bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/chat-type/dist/ChatType.app")
    )

    #expect(guidance.detail?.contains("/Users/tester/Projects/chat-type/dist/ChatType.app") == true)
    #expect(guidance.detail?.contains("click +") == true)
}
