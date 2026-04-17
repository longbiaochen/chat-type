import AppKit
import Foundation

@MainActor
final class OverlayController {
    private let panel: NSPanel
    private let visualEffectView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        configureViews()
    }

    func showRecording() {
        configure(
            symbolName: "waveform.circle.fill",
            tintColor: NSColor.systemOrange,
            title: "Listening",
            subtitle: "Press F5 again to finish dictation",
            preview: "Audio is being recorded for transcription and cleanup.",
            isProcessing: false
        )
        present()
    }

    func showProcessing(provider: String) {
        configure(
            symbolName: "wand.and.stars",
            tintColor: NSColor.systemBlue,
            title: "Processing",
            subtitle: provider,
            preview: "Transcribing, polishing, and preparing the final text.",
            isProcessing: true
        )
        present()
    }

    func showResult(text: String, outcome: InjectionOutcome) {
        let presentation: (symbolName: String, tintColor: NSColor, title: String, subtitle: String)
        switch outcome {
        case .pasted:
            presentation = (
                symbolName: "checkmark.circle.fill",
                tintColor: NSColor.systemGreen,
                title: "Pasted",
                subtitle: "Inserted into the focused app."
            )
        case .copiedToClipboard(let reason):
            presentation = (
                symbolName: "doc.on.clipboard.fill",
                tintColor: NSColor.systemYellow,
                title: "Copied to Clipboard",
                subtitle: reason.overlaySubtitle
            )
        }

        configure(
            symbolName: presentation.symbolName,
            tintColor: presentation.tintColor,
            title: presentation.title,
            subtitle: presentation.subtitle,
            preview: previewText(for: text),
            isProcessing: false
        )
        present()
        scheduleHide(afterSeconds: 1.8)
    }

    func showError(_ message: String) {
        configure(
            symbolName: "exclamationmark.triangle.fill",
            tintColor: NSColor.systemRed,
            title: "Something went wrong",
            subtitle: "The text was not inserted.",
            preview: previewText(for: message),
            isProcessing: false
        )
        present()
        scheduleHide(afterSeconds: 2.4)
    }

    private func configure(
        symbolName: String,
        tintColor: NSColor,
        title: String,
        subtitle: String,
        preview: String,
        isProcessing: Bool
    ) {
        hideTask?.cancel()
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            iconView.image = image
            iconView.contentTintColor = tintColor
        }

        spinner.isHidden = !isProcessing
        if isProcessing {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }

        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        previewLabel.stringValue = preview
    }

    private func present() {
        positionPanel()
        if panel.alphaValue == 0 || !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func scheduleHide(afterSeconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    private func configureViews() {
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 24
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = container
        container.addSubview(visualEffectView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 28, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyUpOrDown

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.74)

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = .systemFont(ofSize: 13, weight: .regular)
        previewLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail

        let titleRow = NSStackView(views: [titleLabel, spinner])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.orientation = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .centerY

        let textStack = NSStackView(views: [titleRow, subtitleLabel, previewLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 6
        textStack.alignment = .leading

        visualEffectView.addSubview(iconView)
        visualEffectView.addSubview(textStack)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 22),
            iconView.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -20),
            textStack.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
        ])
    }

    private func positionPanel() {
        let screen = activeScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = panel.frame.width
        let height = panel.frame.height
        let origin = NSPoint(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.minY + 92
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }

    private func previewText(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 110 {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 110)
        return String(trimmed[..<index]) + "…"
    }
}
