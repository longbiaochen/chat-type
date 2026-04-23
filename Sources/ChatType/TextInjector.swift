import AppKit
import ApplicationServices
import Foundation
import OSLog

struct EditableTextSnapshot: Sendable, Equatable {
    let value: String
    let selectedRange: CFRange

    static func == (lhs: EditableTextSnapshot, rhs: EditableTextSnapshot) -> Bool {
        lhs.value == rhs.value &&
            lhs.selectedRange.location == rhs.selectedRange.location &&
            lhs.selectedRange.length == rhs.selectedRange.length
    }
}

struct DirectTextMutation: Sendable, Equatable {
    let updatedValue: String
    let updatedSelectedRange: CFRange

    static func == (lhs: DirectTextMutation, rhs: DirectTextMutation) -> Bool {
        lhs.updatedValue == rhs.updatedValue &&
            lhs.updatedSelectedRange.location == rhs.updatedSelectedRange.location &&
            lhs.updatedSelectedRange.length == rhs.updatedSelectedRange.length
    }
}

enum TextInsertionPlan: Sendable, Equatable {
    case directInsert(DirectTextMutation)
    case keyPressPaste
    case clipboardFallback(reason: ClipboardFallbackReason)
}

struct LaunchAppContext: Sendable, Equatable {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t

    @MainActor
    static func current() -> LaunchAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return LaunchAppContext(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier
        )
    }
}

enum InjectionError: LocalizedError {
    case keyEventFailed

    var errorDescription: String? {
        switch self {
        case .keyEventFailed:
            return "生成 Cmd+V 事件失败。"
        }
    }
}

enum ClipboardFallbackReason: Sendable, Equatable {
    case accessibilityPermissionRequired
    case noEditableTarget

    var statusDetail: String {
        switch self {
        case .accessibilityPermissionRequired:
            return "Copied to clipboard. Grant Accessibility access for auto-paste."
        case .noEditableTarget:
            return "Copied to clipboard"
        }
    }

    var overlaySubtitle: String {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is off, so ChatType left the text in the clipboard."
        case .noEditableTarget:
            return "No editable cursor was found. Paste manually."
        }
    }
}

enum InjectionOutcome: Sendable, Equatable {
    case pasted
    case copiedToClipboard(reason: ClipboardFallbackReason)
}

@MainActor
protocol TextInjecting: AnyObject {
    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?
    ) throws -> InjectionOutcome
}

@MainActor
final class TextInjector: TextInjecting {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.longbiaochen.chattype",
        category: "TextInjector"
    )

    nonisolated static func injectionOutcome(
        hasEditableTextFocus: Bool,
        accessibilityTrusted: Bool
    ) -> InjectionOutcome {
        guard accessibilityTrusted else {
            return .copiedToClipboard(reason: .accessibilityPermissionRequired)
        }
        guard hasEditableTextFocus else {
            return .copiedToClipboard(reason: .noEditableTarget)
        }
        return .pasted
    }

    nonisolated static func directInsertionMutation(
        text: String,
        snapshot: EditableTextSnapshot
    ) -> DirectTextMutation? {
        let currentValue = snapshot.value as NSString
        let selectedRange = snapshot.selectedRange
        let upperBound = selectedRange.location + selectedRange.length

        guard
            selectedRange.location >= 0,
            selectedRange.length >= 0,
            selectedRange.location <= currentValue.length,
            upperBound <= currentValue.length
        else {
            return nil
        }

        let updatedValue = currentValue.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: text
        )
        let insertedLength = (text as NSString).length
        return DirectTextMutation(
            updatedValue: updatedValue,
            updatedSelectedRange: CFRange(
                location: selectedRange.location + insertedLength,
                length: 0
            )
        )
    }

    nonisolated static func injectionPlan(
        text: String,
        accessibilityTrusted: Bool,
        editableTextSnapshot: EditableTextSnapshot?,
        fallbackEditableTextSnapshot: EditableTextSnapshot?,
        hasEditableTextFocus: Bool,
        hasFallbackEditableTextFocus: Bool
    ) -> TextInsertionPlan {
        guard accessibilityTrusted else {
            return .clipboardFallback(reason: .accessibilityPermissionRequired)
        }

        if let editableTextSnapshot,
           !isPlaceholderOnlySnapshot(editableTextSnapshot),
           let mutation = directInsertionMutation(text: text, snapshot: editableTextSnapshot) {
            return .directInsert(mutation)
        }

        if let fallbackEditableTextSnapshot,
           !isPlaceholderOnlySnapshot(fallbackEditableTextSnapshot),
           let mutation = directInsertionMutation(text: text, snapshot: fallbackEditableTextSnapshot) {
            return .directInsert(mutation)
        }

        guard hasEditableTextFocus || hasFallbackEditableTextFocus else {
            return .clipboardFallback(reason: .noEditableTarget)
        }

        return .keyPressPaste
    }

    private nonisolated static func isPlaceholderOnlySnapshot(_ snapshot: EditableTextSnapshot) -> Bool {
        let normalizedValue = snapshot.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard Self.knownPlaceholderValues.contains(normalizedValue) else {
            return false
        }

        return snapshot.selectedRange.length == 0
    }

    private nonisolated static let knownPlaceholderValues: Set<String> = [
        "ask for follow-up changes",
        "ask codex anything. @ to use plugins or use files",
        "ask codex anything, @ add files, / for commands, $ for skills",
    ]

    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?
    ) throws -> InjectionOutcome {
        let accessibilityTrusted = AccessibilityPermission.isTrusted()
        if !accessibilityTrusted {
            AccessibilityPermission.requestTrustIfNeeded()
        }

        let editableTextTarget = accessibilityTrusted ? FocusedElementInspector.editableTextTarget() : nil
        let fallbackTarget = accessibilityTrusted ? FocusedElementInspector.editableTextTarget(in: launchAppContext) : nil
        let hasEditableTextFocus = accessibilityTrusted && (
            editableTextTarget != nil || FocusedElementInspector.hasEditableTextFocus()
        )
        let hasFallbackEditableTextFocus = accessibilityTrusted && (
            fallbackTarget != nil || FocusedElementInspector.hasEditableTextFocus(in: launchAppContext)
        )
        let plan = Self.injectionPlan(
            text: text,
            accessibilityTrusted: accessibilityTrusted,
            editableTextSnapshot: editableTextTarget?.snapshot,
            fallbackEditableTextSnapshot: fallbackTarget?.snapshot,
            hasEditableTextFocus: hasEditableTextFocus,
            hasFallbackEditableTextFocus: hasFallbackEditableTextFocus
        )

        logger.info(
            "Injection plan resolved to \(String(describing: plan), privacy: .public); currentEditableTarget=\(editableTextTarget != nil, privacy: .public); fallbackEditableTarget=\(fallbackTarget != nil, privacy: .public); currentEditableFocus=\(hasEditableTextFocus, privacy: .public); fallbackEditableFocus=\(hasFallbackEditableTextFocus, privacy: .public)"
        )

        switch plan {
        case .clipboardFallback(let reason):
            copyToPasteboard(text)
            return .copiedToClipboard(reason: reason)
        case .directInsert(let mutation):
            if let editableTextTarget,
               FocusedElementInspector.apply(mutation: mutation, to: editableTextTarget) {
                copyToPasteboardIfNeeded(text, preserveClipboard: preserveClipboard)
                return .pasted
            }
            if let fallbackTarget,
               FocusedElementInspector.apply(mutation: mutation, to: fallbackTarget) {
                copyToPasteboardIfNeeded(text, preserveClipboard: preserveClipboard)
                return .pasted
            }
            return try pasteUsingClipboard(
                text: text,
                preserveClipboard: preserveClipboard,
                restoreDelayMilliseconds: restoreDelayMilliseconds,
                launchAppContext: launchAppContext
            )
        case .keyPressPaste:
            return try pasteUsingClipboard(
                text: text,
                preserveClipboard: preserveClipboard,
                restoreDelayMilliseconds: restoreDelayMilliseconds,
                launchAppContext: launchAppContext
            )
        }
    }

    private func pasteUsingClipboard(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?
    ) throws -> InjectionOutcome {
        let pasteboard = NSPasteboard.general
        let snapshot = preserveClipboard ? PasteboardSnapshot.capture(from: pasteboard) : nil

        restoreLaunchAppIfNeeded(launchAppContext)
        copyToPasteboard(text)

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            throw InjectionError.keyEventFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        if let snapshot {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: restoreDelayMilliseconds * 1_000_000)
                snapshot.restore(to: pasteboard)
            }
        }

        return .pasted
    }

    private func restoreLaunchAppIfNeeded(_ launchAppContext: LaunchAppContext?) {
        guard
            let launchAppContext,
            let currentFrontmostApp = NSWorkspace.shared.frontmostApplication,
            currentFrontmostApp.processIdentifier != launchAppContext.processIdentifier,
            let app = NSRunningApplication(processIdentifier: launchAppContext.processIdentifier)
        else {
            return
        }

        let bundleIdentifier = launchAppContext.bundleIdentifier ?? "unknown"
        logger.info(
            "Reactivating launch app before paste: pid=\(launchAppContext.processIdentifier, privacy: .public) bundleID=\(bundleIdentifier, privacy: .public)"
        )
        app.activate(options: [.activateIgnoringOtherApps])
        usleep(120_000)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copyToPasteboardIfNeeded(_ text: String, preserveClipboard: Bool) {
        guard !preserveClipboard else {
            return
        }

        copyToPasteboard(text)
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let snapshot = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        return PasteboardSnapshot(items: snapshot)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item {
                pasteboardItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([pasteboardItem])
        }
    }
}
