import Foundation

enum AppLaunchMode: Equatable {
    case normal
    case overlayDemo
    case benchmark

    static func resolve(environment: [String: String]) -> AppLaunchMode {
        let benchmarkValue = environment["CHATTYPE_BENCHMARK"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch benchmarkValue {
        case "1", "true", "yes", "benchmark":
            return .benchmark
        default:
            break
        }

        let rawValue = environment["VOICEDEX_OVERLAY_DEMO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch rawValue {
        case "1", "true", "yes", "demo":
            return .overlayDemo
        default:
            return .normal
        }
    }
}
