import Testing
@testable import ChatType

struct AppLaunchModeTests {
    @Test
    func overlayDemoModeRequiresExplicitFlag() {
        #expect(AppLaunchMode.resolve(environment: [:]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["VOICEDEX_OVERLAY_DEMO": "0"]) == .normal)
        #expect(AppLaunchMode.resolve(environment: ["VOICEDEX_OVERLAY_DEMO": "false"]) == .normal)
    }

    @Test
    func overlayDemoModeAcceptsCommonTruthyFlags() {
        #expect(AppLaunchMode.resolve(environment: ["VOICEDEX_OVERLAY_DEMO": "1"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: ["VOICEDEX_OVERLAY_DEMO": "true"]) == .overlayDemo)
        #expect(AppLaunchMode.resolve(environment: ["VOICEDEX_OVERLAY_DEMO": "demo"]) == .overlayDemo)
    }

    @Test
    func benchmarkModeHasPriorityWhenExplicitlyEnabled() {
        #expect(AppLaunchMode.resolve(environment: ["CHATTYPE_BENCHMARK": "1"]) == .benchmark)
        #expect(
            AppLaunchMode.resolve(
                environment: [
                    "CHATTYPE_BENCHMARK": "true",
                    "VOICEDEX_OVERLAY_DEMO": "1",
                ]
            ) == .benchmark
        )
    }
}
