import CoreGraphics
import Testing
@testable import ChatType

@Test
func minimalOverlayPresetUsesNineBarVoiceGlyph() {
    let preset = OverlayStylePreset.typeWhisperMinimal

    #expect(preset.pillWidth == 220)
    #expect(preset.pillHeight == 56)
    #expect(preset.cornerRadius == 18)
    #expect(preset.waveformBarCount == 9)
    #expect(preset.showsTranscriptPreview == false)
}

@Test
func overlayStatesStillDifferentiateLeadingVisualFamilies() {
    #expect(OverlayVisualState.recording(levels: Array(repeating: 0.2, count: 9), elapsedText: "00:03").leadingVisual == .waveform)
    #expect(OverlayVisualState.processing.leadingVisual == .spinner)
    #expect(OverlayVisualState.success(.pasted).leadingVisual == .icon(symbolName: "checkmark.circle.fill"))
    #expect(OverlayVisualState.error("Microphone permission is missing").leadingVisual == .icon(symbolName: "exclamationmark.triangle.fill"))
}

@Test
func overlayStatesStayCompactExceptErrors() {
    #expect(OverlayVisualState.recording(levels: Array(repeating: 0.2, count: 9), elapsedText: "00:03").allowsSupplementaryText == false)
    #expect(OverlayVisualState.processing.allowsSupplementaryText == false)
    #expect(OverlayVisualState.success(.pasted).allowsSupplementaryText == false)
    #expect(OverlayVisualState.error("Microphone permission is missing").allowsSupplementaryText == true)
}

@Test
func recordingOverlayStateShowsCancelControlAndTimer() {
    let state = OverlayVisualState.recording(
        levels: Array(repeating: 0.2, count: 9),
        elapsedText: "00:07"
    )

    #expect(state.showsCancelControl == true)
    #expect(state.trailingText == "00:07")
}

@Test
func processingOverlayStateShowsCancelControlWithoutTimer() {
    #expect(OverlayVisualState.processing.showsCancelControl == true)
    #expect(OverlayVisualState.processing.trailingText == nil)
}

@Test
func successAndErrorStatesRemainNonInteractive() {
    #expect(OverlayVisualState.success(.pasted).showsCancelControl == false)
    #expect(OverlayVisualState.error("boom").showsCancelControl == false)
}

@Test
func overlayErrorMessageIsCollapsedToSingleShortLine() {
    let state = OverlayVisualState.error("Microphone permission is missing.\nGrant access in Settings and try again after restarting ChatType.")

    #expect(state.supplementaryText == "Microphone permission is missing. Grant access in Settings and try…")
}

@Test
func waveformNormalizerClampsSilenceAndLoudInput() {
    #expect(WaveformNormalizer.normalizedLevel(fromAveragePower: -160) == 0.08)
    #expect(WaveformNormalizer.normalizedLevel(fromAveragePower: 0) == 1)
}

@Test
func waveformNormalizerRecordingProfileStaysSymmetricAndWithinBounds() {
    let smoothed = WaveformNormalizer.smoothedLevels(
        previous: Array(repeating: 0.12, count: 9),
        targetLevel: 0.9,
        barCount: 9
    )

    #expect(smoothed.count == 9)
    #expect(smoothed.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(smoothed[4] > smoothed[0])
    #expect(smoothed[4] > smoothed[8])
    #expect(abs(smoothed[0] - smoothed[8]) < 0.0001)
}

@Test
func waveformNormalizerProcessingPulseTravelsAcrossTheGlyph() {
    let early = WaveformNormalizer.processingPulseLevels(frame: 0, barCount: 9)
    let later = WaveformNormalizer.processingPulseLevels(frame: 5, barCount: 9)

    #expect(early.count == 9)
    #expect(later.count == 9)
    #expect(early.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(later.allSatisfy { $0 >= 0.08 && $0 <= 1 })
    #expect(early != later)
    #expect(early.max() != later.max())
}

@Test
func waveformNormalizerPadsMissingSamplesToTheRequestedWaveCount() {
    let smoothed = WaveformNormalizer.smoothedLevels(
        previous: [0.2, 0.3, 0.4],
        targetLevel: 0.6,
        barCount: 9
    )

    #expect(smoothed.count == 9)
    #expect(smoothed.allSatisfy { $0 >= 0.08 && $0 <= 1 })
}

@Test
func overlayRecordingWidthExpandsToFitTimer() {
    let preset = OverlayStylePreset.typeWhisperMinimal

    #expect(
        preset.width(for: .recording(levels: Array(repeating: 0.2, count: 9), elapsedText: "00:07")) >
            preset.width(for: .processing)
    )
    #expect(preset.width(for: .error("boom")) == preset.errorPillWidth)
}
