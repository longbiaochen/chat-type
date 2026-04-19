import AppKit
import Foundation

enum AppInstallLocation {
    struct LaunchBlocker: Equatable {
        let message: String
    }

    static let applicationsURL = URL(fileURLWithPath: "/Applications/ChatType.app")

    static func launchBlocker(bundleURL: URL = Bundle.main.bundleURL) -> LaunchBlocker? {
        let normalizedBundleURL = bundleURL.standardizedFileURL
        guard normalizedBundleURL != applicationsURL.standardizedFileURL else {
            return nil
        }

        return LaunchBlocker(
            message: "ChatType must be installed to /Applications/ChatType.app before it runs. This copy is at \(normalizedBundleURL.path). Rebuild, install the packaged app to /Applications, then launch that installed copy."
        )
    }

    static func revealApplicationsFolder(workspace: NSWorkspace = .shared) {
        workspace.open(applicationsURL.deletingLastPathComponent())
    }
}
