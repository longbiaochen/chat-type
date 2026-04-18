import AppKit
import ApplicationServices
import Foundation

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
final class TextInjector {
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

    func inject(text: String, preserveClipboard: Bool, restoreDelayMilliseconds: UInt64) throws -> InjectionOutcome {
        let pasteboard = NSPasteboard.general
        let snapshot = preserveClipboard ? PasteboardSnapshot.capture(from: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let accessibilityTrusted = AXIsProcessTrusted()
        let hasEditableTextFocus = accessibilityTrusted && FocusedElementInspector.hasEditableTextFocus()
        let outcome = Self.injectionOutcome(
            hasEditableTextFocus: hasEditableTextFocus,
            accessibilityTrusted: accessibilityTrusted
        )

        guard outcome == .pasted else {
            return outcome
        }

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

        return outcome
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
