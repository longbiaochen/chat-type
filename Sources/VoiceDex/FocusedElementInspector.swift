import ApplicationServices
import Foundation

struct FocusedEditableTextTarget {
    let element: AXUIElement
    let snapshot: EditableTextSnapshot
}

enum FocusedElementInspector {
    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
    ]

    static func hasEditableTextFocus() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        guard let element = focusedElement() else {
            return false
        }

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String,
           textRoles.contains(role) {
            return true
        }

        var selectedTextRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedTextRange
        ) == .success {
            return true
        }

        var selectedText: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        ) == .success
    }

    static func editableTextTarget() -> FocusedEditableTextTarget? {
        guard AXIsProcessTrusted(), let element = focusedElement() else {
            return nil
        }

        return editableTextTarget(for: element)
    }

    static func editableTextTarget(in launchAppContext: LaunchAppContext?) -> FocusedEditableTextTarget? {
        guard
            AXIsProcessTrusted(),
            let launchAppContext,
            launchAppContext.processIdentifier > 0
        else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(launchAppContext.processIdentifier)
        var focusedElement: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard status == .success, let focusedElement else {
            return nil
        }

        let element = focusedElement as! AXUIElement
        return editableTextTarget(for: element)
    }

    private static func editableTextTarget(for element: AXUIElement) -> FocusedEditableTextTarget? {
        guard
            isAttributeSettable(kAXValueAttribute, on: element),
            isAttributeSettable(kAXSelectedTextRangeAttribute, on: element),
            let value = stringValue(for: kAXValueAttribute, on: element),
            let selectedRange = selectedRangeValue(on: element)
        else {
            return nil
        }

        return FocusedEditableTextTarget(
            element: element,
            snapshot: EditableTextSnapshot(
                value: value,
                selectedRange: selectedRange
            )
        )
    }

    static func apply(
        mutation: DirectTextMutation,
        to target: FocusedEditableTextTarget
    ) -> Bool {
        var updatedSelectedRange = mutation.updatedSelectedRange
        guard
            let selectedRangeValue = AXValueCreate(.cfRange, &updatedSelectedRange),
            AXUIElementSetAttributeValue(
                target.element,
                kAXValueAttribute as CFString,
                mutation.updatedValue as CFTypeRef
            ) == .success,
            AXUIElementSetAttributeValue(
                target.element,
                kAXSelectedTextRangeAttribute as CFString,
                selectedRangeValue
            ) == .success
        else {
            return false
        }

        return true
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard
            focusedStatus == .success,
            let focusedElement
        else {
            return nil
        }

        let element: AXUIElement = focusedElement as! AXUIElement
        return element
    }

    private static func isAttributeSettable(
        _ attribute: String,
        on element: AXUIElement
    ) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    private static func stringValue(
        for attribute: String,
        on element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func selectedRangeValue(on element: AXUIElement) -> CFRange? {
        var selectedTextRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedTextRange
        ) == .success,
        let selectedTextRange,
        CFGetTypeID(selectedTextRange) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = selectedTextRange as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }
}
