import AppKit
import ApplicationServices
import Foundation
import Security

enum AccessibilityPermission {
    typealias TrustCheck = () -> Bool
    typealias TrustPrompt = () -> Bool

    struct RepairGuidance: Sendable, Equatable {
        let subtitle: String
        let detail: String?
    }

    enum SignatureState: Sendable, Equatable {
        case stable(teamIdentifier: String)
        case adHocOrUnsigned
        case unavailable
    }

    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"
    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    static func isTrusted(
        trustCheck: TrustCheck = { AXIsProcessTrusted() }
    ) -> Bool {
        trustCheck()
    }

    @discardableResult
    static func requestTrustIfNeeded(
        trustCheck: TrustCheck = { AXIsProcessTrusted() },
        prompt: TrustPrompt = {
            let options = [
                promptOptionKey: true,
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    ) -> Bool {
        guard !trustCheck() else {
            return true
        }

        return prompt()
    }

    static func openAccessibilitySettings(workspace: NSWorkspace = .shared) {
        guard let accessibilitySettingsURL else {
            return
        }

        workspace.open(accessibilitySettingsURL)
    }

    static func signatureState(bundleURL: URL = Bundle.main.bundleURL) -> SignatureState {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return .unavailable
        }

        var signingInformation: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard copyStatus == errSecSuccess,
              let signingInformation,
              let signingInfo = signingInformation as? [String: Any] else {
            return .unavailable
        }

        return signatureState(signingInformation: signingInfo)
    }

    static func repairGuidance(
        appName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "ChatType",
        signatureState: SignatureState = signatureState(),
        bundleURL: URL = Bundle.main.bundleURL
    ) -> RepairGuidance {
        let subtitle = "Allow Accessibility for \(appName) so it can send Cmd+V to the active text cursor. Until then, it only copies to the clipboard."

        var details: [String] = []

        switch signatureState {
        case .stable:
            break
        case .adHocOrUnsigned:
            details.append(
                "This build is ad-hoc signed or missing a stable team identity, so macOS may open Accessibility without creating a toggle for \(appName). Repackage it with Apple Development signing, reopen the packaged app, then request access again."
            )
        case .unavailable:
            details.append(
                "ChatType could not inspect its own code signature. If Accessibility opens without a \(appName) row, rebuild the packaged app before requesting access again."
            )
        }

        if isInstalledInApplications(bundleURL: bundleURL) {
            details.append("If \(appName) still does not appear in the list, click + in Accessibility and add the running app again.")
        } else {
            details.append("If \(appName) still does not appear in the list, click + in Accessibility and add this app manually: \(bundleURL.path)")
        }

        return RepairGuidance(
            subtitle: subtitle,
            detail: details.joined(separator: " ")
        )
    }

    private static func signatureState(signingInformation: [String: Any]) -> SignatureState {
        if let teamIdentifier = signingInformation[kSecCodeInfoTeamIdentifier as String] as? String,
           !teamIdentifier.isEmpty {
            return .stable(teamIdentifier: teamIdentifier)
        }

        return .adHocOrUnsigned
    }

    private static func isInstalledInApplications(bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }
}
