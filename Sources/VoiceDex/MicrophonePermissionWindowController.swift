import AppKit
import SwiftUI

@MainActor
final class MicrophonePermissionWindowController: NSWindowController, NSWindowDelegate {
    private var completion: ((Bool) -> Void)?

    init() {
        let view = MicrophonePermissionView(
            onContinue: {},
            onCancel: {}
        )
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Enable Microphone Access"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        window.level = .normal
        window.contentViewController = hostingController

        super.init(window: window)

        hostingController.rootView = MicrophonePermissionView(
            onContinue: { [weak self] in
                self?.finish(with: true)
            },
            onCancel: { [weak self] in
                self?.finish(with: false)
            }
        )
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() async -> Bool {
        await withCheckedContinuation { continuation in
            completion = { decision in
                continuation.resume(returning: decision)
            }
            show()
        }
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: false)
    }

    private func finish(with decision: Bool) {
        guard let completion else {
            return
        }

        self.completion = nil
        window?.orderOut(nil)
        completion(decision)
    }
}

private struct MicrophonePermissionView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow microphone access")
                .font(.system(size: 24, weight: .semibold))

            Text("ChatType needs microphone access before it can record your first dictation. Click Continue and macOS should show the microphone permission prompt next.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Installed app path: /Applications/ChatType.app", systemImage: "checkmark.circle.fill")
                Label("First-run permission is requested only once from a clean TCC state", systemImage: "mic.circle")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
