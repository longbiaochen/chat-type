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

        return isEditableTextFocus(element)
    }

    static func hasEditableTextFocus(in launchAppContext: LaunchAppContext?) -> Bool {
        guard
            AXIsProcessTrusted(),
            let launchAppContext,
            launchAppContext.processIdentifier > 0,
            let element = preferredFocusedElement(in: launchAppContext)
        else {
            return false
        }

        return isEditableTextFocus(element)
    }

    private static func isEditableTextFocus(_ element: AXUIElement) -> Bool {
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
            launchAppContext.processIdentifier > 0,
            let element = preferredFocusedElement(in: launchAppContext)
        else {
            return nil
        }

        return editableTextTarget(for: element)
    }

    private static func focusedElement(in launchAppContext: LaunchAppContext) -> AXUIElement? {
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
        return element
    }

    private static func preferredFocusedElement(in launchAppContext: LaunchAppContext) -> AXUIElement? {
        if let element = focusedElement(in: launchAppContext) {
            return element
        }

        guard let focusedWindow = focusedWindow(in: launchAppContext) else {
            return nil
        }

        return firstEditableDescendant(in: focusedWindow)
    }

    private static func focusedWindow(in launchAppContext: LaunchAppContext) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(launchAppContext.processIdentifier)
        var focusedWindow: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard status == .success, let focusedWindow else {
            return nil
        }

        return (focusedWindow as! AXUIElement)
    }

    private static func firstEditableDescendant(in root: AXUIElement) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var seen = Set<CFHashCode>()

        while !queue.isEmpty {
            let element = queue.removeFirst()
            let hash = CFHash(element)
            guard !seen.contains(hash) else {
                continue
            }
            seen.insert(hash)

            if isEditableCandidate(element) {
                return element
            }

            queue.append(contentsOf: childElements(of: element, attribute: "AXChildrenInNavigationOrder"))
            queue.append(contentsOf: childElements(of: element, attribute: kAXChildrenAttribute as String))
        }

        return nil
    }

    private static func isEditableCandidate(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String,
           textRoles.contains(role) {
            return true
        }

        return isAttributeSettable(kAXValueAttribute, on: element) &&
            isAttributeSettable(kAXSelectedTextRangeAttribute, on: element)
    }

    private static func childElements(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }

        return (value as? [AXUIElement]) ?? []
    }

    private static func editableTextTarget(for element: AXUIElement) -> FocusedEditableTextTarget? {
        guard hasDirectTextRole(element) else {
            return nil
        }

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

    private static func hasDirectTextRole(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else {
            return false
        }

        return textRoles.contains(role)
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
