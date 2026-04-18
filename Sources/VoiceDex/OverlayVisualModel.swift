import CoreGraphics
import Foundation

struct OverlayStylePreset: Sendable, Equatable {
    let pillWidth: CGFloat
    let pillHeight: CGFloat
    let errorPillWidth: CGFloat
    let cornerRadius: CGFloat
    let leadingVisualWidth: CGFloat
    let leadingVisualHeight: CGFloat
    let waveformBarCount: Int
    let waveformBarSpacing: CGFloat
    let waveformMinimumBarHeight: CGFloat
    let showsTranscriptPreview: Bool
    let recordingAutoHideDelay: TimeInterval?
    let processingAutoHideDelay: TimeInterval?
    let successAutoHideDelay: TimeInterval?
    let errorAutoHideDelay: TimeInterval?

    static let typeWhisperMinimal = OverlayStylePreset(
        pillWidth: 220,
        pillHeight: 56,
        errorPillWidth: 320,
        cornerRadius: 18,
        leadingVisualWidth: 76,
        leadingVisualHeight: 30,
        waveformBarCount: 9,
        waveformBarSpacing: 4,
        waveformMinimumBarHeight: 6,
        showsTranscriptPreview: false,
        recordingAutoHideDelay: nil,
        processingAutoHideDelay: nil,
        successAutoHideDelay: 1.2,
        errorAutoHideDelay: 2.0
    )
}

enum OverlayLeadingVisual: Sendable, Equatable {
    case waveform
    case spinner
    case icon(symbolName: String)
}

enum OverlaySuccessKind: Sendable, Equatable {
    case pasted
    case copied

    var label: String {
        switch self {
        case .pasted:
            return "Pasted"
        case .copied:
            return "Copied"
        }
    }
}

enum OverlayVisualState: Sendable, Equatable {
    case recording(levels: [CGFloat])
    case processing
    case success(OverlaySuccessKind)
    case error(String)

    var label: String {
        switch self {
        case .recording:
            return "Listening"
        case .processing:
            return "Processing"
        case .success(let kind):
            return kind.label
        case .error:
            return "Error"
        }
    }

    var leadingVisual: OverlayLeadingVisual {
        switch self {
        case .recording:
            return .waveform
        case .processing:
            return .spinner
        case .success(let kind):
            return .icon(symbolName: kind == .pasted ? "checkmark.circle.fill" : "doc.on.clipboard.fill")
        case .error:
            return .icon(symbolName: "exclamationmark.triangle.fill")
        }
    }

    var allowsSupplementaryText: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    var supplementaryText: String? {
        guard case .error(let message) = self else {
            return nil
        }
        return Self.collapseErrorMessage(message)
    }

    private static func collapseErrorMessage(_ message: String) -> String {
        let collapsed = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let characterLimit = 70
        guard collapsed.count > characterLimit else {
            return collapsed
        }

        let limitIndex = collapsed.index(collapsed.startIndex, offsetBy: characterLimit)
        let prefix = String(collapsed[..<limitIndex])
        let trimmed = prefix[..<(prefix.lastIndex(of: " ") ?? prefix.endIndex)]
        return String(trimmed) + "…"
    }
}

enum WaveformNormalizer {
    static let minimumVisibleLevel: CGFloat = 0.08
    static let maximumVisibleLevel: CGFloat = 1
    private static let silenceFloor: Float = -160
    private static let smoothingFactor: CGFloat = 0.34

    static func normalizedLevel(fromAveragePower averagePower: Float) -> CGFloat {
        if averagePower >= 0 {
            return maximumVisibleLevel
        }
        let clamped = max(silenceFloor, min(0, averagePower))
        let normalized = 1 - CGFloat(abs(clamped) / abs(silenceFloor))
        return min(maximumVisibleLevel, max(minimumVisibleLevel, normalized))
    }

    static func smoothedLevels(
        previous: [CGFloat],
        targetLevel: CGFloat,
        barCount: Int
    ) -> [CGFloat] {
        let seed = Array(previous.prefix(barCount))
        let padded = seed + Array(repeating: minimumVisibleLevel, count: max(0, barCount - seed.count))
        let target = min(maximumVisibleLevel, max(minimumVisibleLevel, targetLevel))

        let center = CGFloat(max(0, barCount - 1)) / 2
        let radius = max(center, 1)

        return padded.enumerated().map { index, prior in
            let distanceFromCenter = abs(CGFloat(index) - center) / radius
            let contour = pow(max(0, 1 - distanceFromCenter), 1.35)
            let weightedTarget = minimumVisibleLevel + ((target - minimumVisibleLevel) * (0.42 + (contour * 0.58)))
            let next = prior + ((weightedTarget - prior) * smoothingFactor)
            return min(maximumVisibleLevel, max(minimumVisibleLevel, next))
        }
    }

    static func processingPulseLevels(frame: Int, barCount: Int) -> [CGFloat] {
        let center = CGFloat(max(0, barCount - 1)) / 2
        let radius = max(center, 1)
        let phase = CGFloat(frame % max(1, barCount + 4)) - 2

        return (0..<barCount).map { index in
            let distanceFromCenter = abs(CGFloat(index) - center) / radius
            let contour = pow(max(0, 1 - distanceFromCenter), 1.25)
            let envelope = minimumVisibleLevel + (contour * 0.22)
            let pulseDistance = abs(CGFloat(index) - phase)
            let ridge = max(0, 1 - (pulseDistance / 2.2))
            let level = envelope + (ridge * 0.58)
            return min(maximumVisibleLevel, max(minimumVisibleLevel, level))
        }
    }
}
