import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol OverlayControlling: AnyObject {
    var onCancel: (@MainActor () -> Void)? { get set }

    func showRecording(elapsedText: String)
    func updateRecording(level: CGFloat, elapsedText: String)
    func showProcessing()
    func showResult(text: String, outcome: InjectionOutcome)
    func showError(_ message: String)
    func hide()
}

@MainActor
final class OverlayController: OverlayControlling {
    private let style = OverlayStylePreset.typeWhisperMinimal
    private let panel: NSPanel
    private let closeControlPanel: NSPanel
    private let backgroundView = NSView()
    private let leadingContainer = NSView()
    private let leadingBadgeView = NSView()
    private let waveformView: OverlayWaveformView
    private let iconView = NSImageView()
    private let closeButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let trailingTimerLabel = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?
    private var processingTimer: Timer?
    private var processingFrameIndex = 0
    private var displayedLevels: [CGFloat]
    private var currentState: OverlayVisualState
    private var escapeHotkeyMonitor: HotkeyMonitor?
    var onCancel: (@MainActor () -> Void)?

    init(onCancel: (@MainActor () -> Void)? = nil) {
        displayedLevels = Array(
            repeating: WaveformNormalizer.minimumVisibleLevel,
            count: style.waveformBarCount
        )
        currentState = .processing
        waveformView = OverlayWaveformView(
            levels: displayedLevels,
            style: style
        )
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: style.pillWidth, height: style.pillHeight),
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
        closeControlPanel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: style.closeControlDiameter + 8,
                height: style.closeControlDiameter + 8
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        closeControlPanel.isFloatingPanel = true
        closeControlPanel.level = .statusBar
        closeControlPanel.backgroundColor = .clear
        closeControlPanel.hasShadow = false
        closeControlPanel.isOpaque = false
        closeControlPanel.hidesOnDeactivate = false
        closeControlPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        closeControlPanel.ignoresMouseEvents = false
        self.onCancel = onCancel

        configureViews()
        configureCloseControl()
    }

    func showRecording(elapsedText: String) {
        stopProcessingAnimation()
        displayedLevels = Array(
            repeating: WaveformNormalizer.minimumVisibleLevel,
            count: style.waveformBarCount
        )
        apply(state: .recording(levels: displayedLevels, elapsedText: elapsedText))
        present()
    }

    func updateRecording(level: CGFloat, elapsedText: String) {
        stopProcessingAnimation()
        displayedLevels = WaveformNormalizer.smoothedLevels(
            previous: displayedLevels,
            targetLevel: level,
            barCount: style.waveformBarCount
        )
        apply(state: .recording(levels: displayedLevels, elapsedText: elapsedText))
        present()
    }

    func showProcessing() {
        processingFrameIndex = 0
        displayedLevels = WaveformNormalizer.processingPulseLevels(
            frame: processingFrameIndex,
            barCount: style.waveformBarCount
        )
        apply(state: .processing)
        present()
        startProcessingAnimation()
    }

    func showResult(text: String, outcome: InjectionOutcome) {
        _ = text
        stopProcessingAnimation()

        let successKind: OverlaySuccessKind
        switch outcome {
        case .pasted:
            successKind = .pasted
        case .copiedToClipboard:
            successKind = .copied
        }

        apply(state: .success(successKind))
        present()
        scheduleHide(afterSeconds: style.successAutoHideDelay ?? 1.2)
    }

    func showError(_ message: String) {
        stopProcessingAnimation()
        apply(state: .error(message))
        present()
        scheduleHide(afterSeconds: style.errorAutoHideDelay ?? 2.0)
    }

    func hide() {
        hideTask?.cancel()
        stopProcessingAnimation()
        hideSessionControls()
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private func apply(state: OverlayVisualState) {
        hideTask?.cancel()
        currentState = state
        positionPanel(size: panelSize(for: state))

        titleLabel.stringValue = state.label
        detailLabel.stringValue = state.supplementaryText ?? ""
        detailLabel.isHidden = !state.allowsSupplementaryText
        trailingTimerLabel.stringValue = state.trailingText ?? ""
        trailingTimerLabel.isHidden = state.trailingText == nil
        updateSessionControls(for: state)

        switch state {
        case .recording(let levels, _):
            displayedLevels = levels
            waveformView.isHidden = false
            waveformView.update(levels: levels)
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
        case .processing:
            waveformView.isHidden = false
            waveformView.update(levels: displayedLevels)
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
        case .success(let kind):
            waveformView.isHidden = true
            configureBadge(
                symbolName: kind == .pasted ? "checkmark" : "doc.on.clipboard.fill",
                tintColor: kind == .pasted ? ChatTypePalette.success : ChatTypePalette.amber,
                fillColor: kind == .pasted ? ChatTypePalette.success.withAlphaComponent(0.14) : ChatTypePalette.amber.withAlphaComponent(0.16),
                borderColor: kind == .pasted ? ChatTypePalette.success.withAlphaComponent(0.34) : ChatTypePalette.amber.withAlphaComponent(0.38)
            )
        case .error:
            waveformView.isHidden = true
            configureBadge(
                symbolName: "exclamationmark",
                tintColor: ChatTypePalette.error,
                fillColor: ChatTypePalette.error.withAlphaComponent(0.15),
                borderColor: ChatTypePalette.error.withAlphaComponent(0.34)
            )
        }
    }

    private func configureBadge(
        symbolName: String,
        tintColor: NSColor,
        fillColor: NSColor,
        borderColor: NSColor
    ) {
        leadingBadgeView.isHidden = false
        leadingBadgeView.layer?.backgroundColor = fillColor.cgColor
        leadingBadgeView.layer?.borderColor = borderColor.cgColor

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            iconView.image = image
            iconView.contentTintColor = tintColor
        } else {
            iconView.image = nil
        }

        iconView.isHidden = false
    }

    private func startProcessingAnimation() {
        stopProcessingAnimation()

        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingFrameIndex += 1
                self.displayedLevels = WaveformNormalizer.processingPulseLevels(
                    frame: self.processingFrameIndex,
                    barCount: self.style.waveformBarCount
                )
                if case .processing = self.currentState {
                    self.waveformView.update(levels: self.displayedLevels)
                }
            }
        }
    }

    private func stopProcessingAnimation() {
        processingTimer?.invalidate()
        processingTimer = nil
    }

    private func present() {
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

        if currentState.showsCancelControl {
            closeControlPanel.orderFrontRegardless()
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
                    self.hide()
                }
            })
        }
    }

    private func configureViews() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = container
        container.wantsLayer = true
        container.addSubview(backgroundView)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = ChatTypePalette.graphite.cgColor
        backgroundView.layer?.cornerRadius = style.cornerRadius
        backgroundView.layer?.borderWidth = 1
        backgroundView.layer?.borderColor = ChatTypePalette.mist.withAlphaComponent(0.08).cgColor
        backgroundView.shadow = NSShadow()
        backgroundView.shadow?.shadowBlurRadius = 18
        backgroundView.shadow?.shadowOffset = NSSize(width: 0, height: -2)
        backgroundView.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.35)

        leadingContainer.translatesAutoresizingMaskIntoConstraints = false
        leadingContainer.wantsLayer = false

        leadingBadgeView.translatesAutoresizingMaskIntoConstraints = false
        leadingBadgeView.wantsLayer = true
        leadingBadgeView.layer?.cornerRadius = 18
        leadingBadgeView.layer?.borderWidth = 1
        leadingBadgeView.isHidden = true

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 16, weight: .bold)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = ChatTypePalette.mist
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = ChatTypePalette.mistMuted
        detailLabel.maximumNumberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.isHidden = true

        trailingTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        trailingTimerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        trailingTimerLabel.textColor = ChatTypePalette.mistMuted
        trailingTimerLabel.alignment = .right
        trailingTimerLabel.isHidden = true

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        backgroundView.addSubview(leadingContainer)
        backgroundView.addSubview(textStack)
        backgroundView.addSubview(trailingTimerLabel)
        leadingContainer.addSubview(waveformView)
        leadingContainer.addSubview(leadingBadgeView)
        leadingContainer.addSubview(iconView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            leadingContainer.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 14),
            leadingContainer.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            leadingContainer.widthAnchor.constraint(equalToConstant: style.leadingVisualWidth),
            leadingContainer.heightAnchor.constraint(equalToConstant: style.leadingVisualHeight),

            waveformView.leadingAnchor.constraint(equalTo: leadingContainer.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: leadingContainer.trailingAnchor),
            waveformView.topAnchor.constraint(equalTo: leadingContainer.topAnchor),
            waveformView.bottomAnchor.constraint(equalTo: leadingContainer.bottomAnchor),

            leadingBadgeView.centerXAnchor.constraint(equalTo: leadingContainer.centerXAnchor),
            leadingBadgeView.centerYAnchor.constraint(equalTo: leadingContainer.centerYAnchor),
            leadingBadgeView.widthAnchor.constraint(equalToConstant: 64),
            leadingBadgeView.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: leadingBadgeView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: leadingBadgeView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: leadingContainer.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingTimerLabel.leadingAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

            trailingTimerLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -16),
            trailingTimerLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            trailingTimerLabel.widthAnchor.constraint(equalToConstant: style.trailingTimerWidth),
        ])
    }

    private func panelSize(for state: OverlayVisualState) -> NSSize {
        NSSize(width: style.width(for: state), height: style.pillHeight)
    }

    private func positionPanel(size: NSSize) {
        let screen = activeScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.minY + 116
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        positionCloseControlPanel()
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }

    private func configureCloseControl() {
        let container = NSView(frame: closeControlPanel.contentRect(forFrameRect: closeControlPanel.frame))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        closeControlPanel.contentView = container

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = style.closeControlDiameter / 2
        closeButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.94).cgColor
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel dictation")
        closeButton.symbolConfiguration = .init(pointSize: 7, weight: .bold)
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = NSColor.black.withAlphaComponent(0.72)
        closeButton.target = self
        closeButton.action = #selector(handleCancelControlPressed)

        container.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: style.closeControlDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: style.closeControlDiameter),
        ])
    }

    private func updateSessionControls(for state: OverlayVisualState) {
        if state.showsCancelControl {
            positionCloseControlPanel()
            activateEscapeHotkeyIfNeeded()
        } else {
            hideSessionControls()
        }
    }

    private func positionCloseControlPanel() {
        guard currentState.showsCancelControl else { return }

        let buttonSize = NSSize(
            width: style.closeControlDiameter + 8,
            height: style.closeControlDiameter + 8
        )
        let origin = NSPoint(
            x: panel.frame.minX + style.closeControlInsetX - 4,
            y: panel.frame.maxY - style.closeControlInsetY - buttonSize.height + 4
        )
        closeControlPanel.setFrame(
            NSRect(origin: origin, size: buttonSize),
            display: false
        )
    }

    private func activateEscapeHotkeyIfNeeded() {
        guard escapeHotkeyMonitor == nil else { return }
        escapeHotkeyMonitor = try? HotkeyMonitor(keyCode: 53) { [weak self] in
            Task { @MainActor [weak self] in
                self?.onCancel?()
            }
        }
    }

    private func hideSessionControls() {
        escapeHotkeyMonitor = nil
        closeControlPanel.orderOut(nil)
    }

    @objc
    private func handleCancelControlPressed() {
        onCancel?()
    }
}

@MainActor
private final class OverlayWaveformView: NSView {
    private var levels: [CGFloat]
    private let style: OverlayStylePreset

    init(levels: [CGFloat], style: OverlayStylePreset) {
        self.levels = levels
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(levels: [CGFloat]) {
        let trimmed = Array(levels.prefix(style.waveformBarCount))
        if trimmed.count == style.waveformBarCount {
            self.levels = trimmed
        } else {
            self.levels = trimmed + Array(
                repeating: WaveformNormalizer.minimumVisibleLevel,
                count: max(0, style.waveformBarCount - trimmed.count)
            )
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let activeLevels = levels.isEmpty
            ? Array(repeating: WaveformNormalizer.minimumVisibleLevel, count: style.waveformBarCount)
            : levels

        let totalSpacing = style.waveformBarSpacing * CGFloat(max(0, activeLevels.count - 1))
        let availableWidth = bounds.width - totalSpacing
        let rawBarWidth = availableWidth / CGFloat(max(1, activeLevels.count))
        let barWidth = max(3, min(4, floor(rawBarWidth)))
        let contentWidth = (barWidth * CGFloat(activeLevels.count)) + totalSpacing
        var x = bounds.midX - (contentWidth / 2)
        let center = CGFloat(max(0, activeLevels.count - 1)) / 2

        for (index, level) in activeLevels.enumerated() {
            let barHeight = max(style.waveformMinimumBarHeight, bounds.height * level)
            let barRect = CGRect(
                x: x,
                y: bounds.midY - (barHeight / 2),
                width: barWidth,
                height: barHeight
            )

            let distanceFromCenter = abs(CGFloat(index) - center) / max(1, center)
            let accentMix = (1 - min(1, distanceFromCenter)) * min(1, 0.42 + (level * 0.68))
            let barColor = NSColor.blend(
                from: ChatTypePalette.mist.withAlphaComponent(0.68),
                to: ChatTypePalette.iceBlue,
                amount: accentMix
            )
            barColor.setFill()
            NSBezierPath(
                roundedRect: barRect,
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()

            x += barWidth + style.waveformBarSpacing
        }
    }
}
