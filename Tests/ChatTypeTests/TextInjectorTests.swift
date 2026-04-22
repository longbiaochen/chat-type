import Foundation
import Testing
@testable import ChatType

@Test
func accessibilityRequestSkipsPromptWhenAlreadyTrusted() {
    var didPrompt = false

    let trusted = AccessibilityPermission.requestTrustIfNeeded(
        trustCheck: { true },
        prompt: {
            didPrompt = true
            return true
        }
    )

    #expect(trusted)
    #expect(!didPrompt)
}

@Test
func accessibilityRequestPromptsWhenTrustIsMissing() {
    var didPrompt = false

    let trusted = AccessibilityPermission.requestTrustIfNeeded(
        trustCheck: { false },
        prompt: {
            didPrompt = true
            return false
        }
    )

    #expect(!trusted)
    #expect(didPrompt)
}

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

@Test
func directInsertionMutationInsertsTranscriptAtCaretLocation() {
    let snapshot = EditableTextSnapshot(
        value: "hello world",
        selectedRange: CFRange(location: 6, length: 0)
    )

    let mutation = TextInjector.directInsertionMutation(
        text: "ChatType ",
        snapshot: snapshot
    )

    #expect(
        mutation == DirectTextMutation(
            updatedValue: "hello ChatType world",
            updatedSelectedRange: CFRange(location: 15, length: 0)
        )
    )
}

@Test
func directInsertionMutationReplacesSelectedText() {
    let snapshot = EditableTextSnapshot(
        value: "hello brave world",
        selectedRange: CFRange(location: 6, length: 5)
    )

    let mutation = TextInjector.directInsertionMutation(
        text: "ChatType",
        snapshot: snapshot
    )

    #expect(
        mutation == DirectTextMutation(
            updatedValue: "hello ChatType world",
            updatedSelectedRange: CFRange(location: 14, length: 0)
        )
    )
}

@Test
func injectionPlanPrefersDirectInsertionWhenFocusedTextSnapshotIsAvailable() {
    let snapshot = EditableTextSnapshot(
        value: "hello world",
        selectedRange: CFRange(location: 6, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "ChatType ",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true
    )

    #expect(
        plan == .directInsert(
            DirectTextMutation(
                updatedValue: "hello ChatType world",
                updatedSelectedRange: CFRange(location: 15, length: 0)
            )
        )
    )
}

@Test
func injectionPlanUsesNativePasteWhenFocusedSnapshotIsOnlyCodexPlaceholder() {
    let snapshot = EditableTextSnapshot(
        value: "Ask for follow-up changes",
        selectedRange: CFRange(location: 0, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "ChatType",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanDoesNotPasteWhenOnlyLaunchAppContextExists() {
    let plan = TextInjector.injectionPlan(
        text: "ChatType",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: false
    )

    #expect(plan == .clipboardFallback(reason: .noEditableTarget))
}

@Test
func injectionPlanUsesNativePasteWhenFocusedEditorIsNotDirectlyWritable() {
    let plan = TextInjector.injectionPlan(
        text: "ChatType",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanStillUsesClipboardWhenNoEditorSignalExists() {
    let plan = TextInjector.injectionPlan(
        text: "ChatType",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: false
    )

    #expect(plan == .clipboardFallback(reason: .noEditableTarget))
}
