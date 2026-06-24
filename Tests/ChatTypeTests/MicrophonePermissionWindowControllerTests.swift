import Testing
@testable import ChatType

@MainActor
@Test
func microphonePermissionWindowKeepsUsableMinimumWidth() throws {
    let controller = MicrophonePermissionWindowController()
    let window = try #require(controller.window)

    #expect(window.contentMinSize == MicrophonePermissionWindowLayout.contentSize)
    #expect(window.contentLayoutRect.width >= MicrophonePermissionWindowLayout.contentSize.width)
    #expect(window.contentLayoutRect.height >= MicrophonePermissionWindowLayout.contentSize.height)
}
