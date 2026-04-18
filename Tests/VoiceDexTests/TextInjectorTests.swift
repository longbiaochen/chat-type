import Testing
@testable import ChatType

@Test
func injectionFallsBackToClipboardWithoutAccessibilityPermission() {
    let outcome = TextInjector.injectionOutcome(
        hasEditableTextFocus: true,
        accessibilityTrusted: false
    )

    #expect(outcome == .copiedToClipboard(reason: .accessibilityPermissionRequired))
}

@Test
func injectionFallsBackToClipboardWithoutEditableFocus() {
    let outcome = TextInjector.injectionOutcome(
        hasEditableTextFocus: false,
        accessibilityTrusted: true
    )

    #expect(outcome == .copiedToClipboard(reason: .noEditableTarget))
}

@Test
func injectionPastesWhenEditableFocusAndAccessibilityPermissionAreAvailable() {
    let outcome = TextInjector.injectionOutcome(
        hasEditableTextFocus: true,
        accessibilityTrusted: true
    )

    #expect(outcome == .pasted)
}
