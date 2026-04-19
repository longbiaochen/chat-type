import Foundation

struct LatencySample: Codable, Sendable, Equatable {
    let timestamp: Date
    let audioDurationMs: Int
    let audioBytes: Int
    let provider: String
    let authMs: Int
    let transcribeMs: Int
    let normalizationMs: Int
    let injectMs: Int
    let totalProcessingMs: Int
    let resultStatus: String
    let errorCategory: String?
}

protocol LatencyRecording: Sendable {
    func record(_ sample: LatencySample) throws
}

final class LatencyRecorder: LatencyRecording, @unchecked Sendable {
    private let fileManager: FileManager
    let directoryURL: URL
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ChatType", isDirectory: true)
    }

    func record(_ sample: LatencySample) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let dataURL = directoryURL.appendingPathComponent("latency.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(sample) + Data([0x0A])

        if fileManager.fileExists(atPath: dataURL.path) {
            let handle = try FileHandle(forWritingTo: dataURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: dataURL, options: [.atomic])
        }
    }
}
