import Foundation
import Testing
@testable import ChatType

struct AppInstallLocationTests {
    @Test
    func distBuildsAreRejectedForNormalLaunches() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Projects/chat-type/dist/ChatType.app")
        )

        #expect(blocker != nil)
        #expect(blocker?.message.contains("/Applications/ChatType.app") == true)
        #expect(blocker?.message.contains("/Users/tester/Projects/chat-type/dist/ChatType.app") == true)
    }

    @Test
    func installedApplicationsPathIsAccepted() {
        let blocker = AppInstallLocation.launchBlocker(
            bundleURL: URL(fileURLWithPath: "/Applications/ChatType.app")
        )

        #expect(blocker == nil)
    }
}
