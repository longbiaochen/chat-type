import Foundation

struct AuthStatus: Sendable {
    let authMethod: String
    let authToken: String?
}

final class AuthStatusCache: @unchecked Sendable {
    private struct Entry: Sendable {
        let status: AuthStatus
        let storedAt: Date
    }

    static let shared = AuthStatusCache()

    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var entry: Entry?

    init(
        ttl: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.ttl = ttl
        self.now = now
    }

    func store(_ status: AuthStatus, at timestamp: Date? = nil) {
        lock.lock()
        entry = Entry(status: status, storedAt: timestamp ?? now())
        lock.unlock()
    }

    func cachedStatus(includeToken: Bool, now overrideNow: Date? = nil) -> AuthStatus? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry else {
            return nil
        }

        let currentTime = overrideNow ?? now()
        guard currentTime.timeIntervalSince(entry.storedAt) <= ttl else {
            self.entry = nil
            return nil
        }

        let token = entry.status.authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if includeToken, token.isEmpty {
            return nil
        }
        return entry.status
    }
}

enum CodexAuthError: LocalizedError {
    case launcherNotFound
    case initializeFailed(String)
    case authFailed(String)
    case timedOut(String)
    case malformedResponse
    case notChatGPT
    case missingToken

    var errorDescription: String? {
        switch self {
        case .launcherNotFound:
            return "找不到 Codex app-server，可执行文件不可用。"
        case .initializeFailed(let message):
            return "Codex app-server 初始化失败：\(message)"
        case .authFailed(let message):
            return "Codex 登录态读取失败：\(message)"
        case .timedOut(let stage):
            return "等待 Codex app-server \(stage) 超时。"
        case .malformedResponse:
            return "Codex app-server 返回了无法解析的响应。"
        case .notChatGPT:
            return "当前 Codex 不是 ChatGPT 登录态，无法走 ChatGPT 转写。"
        case .missingToken:
            return "Codex 当前没有可用的 ChatGPT token。"
        }
    }
}

struct CodexAuthClient: Sendable {
    private static let commandCandidates = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "/usr/local/bin/codex",
        "/opt/homebrew/bin/codex",
    ]
    let cache: AuthStatusCache
    let now: @Sendable () -> Date
    let liveFetch: @Sendable (_ includeToken: Bool, _ refreshToken: Bool) throws -> AuthStatus

    init(
        cache: AuthStatusCache = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        liveFetch: @escaping @Sendable (_ includeToken: Bool, _ refreshToken: Bool) throws -> AuthStatus = { includeToken, refreshToken in
            try Self.performLiveFetch(includeToken: includeToken, refreshToken: refreshToken)
        }
    ) {
        self.cache = cache
        self.now = now
        self.liveFetch = liveFetch
    }

    func fetchAuthStatus(
        includeToken: Bool = true,
        refreshToken: Bool = true,
        allowCached: Bool = false
    ) throws -> AuthStatus {
        if allowCached, let cached = cache.cachedStatus(includeToken: includeToken, now: now()) {
            return cached
        }

        let status = try liveFetch(includeToken, refreshToken)
        cache.store(status, at: now())
        return status
    }

    func fetchBestAvailableAuthStatus(includeToken: Bool = true) throws -> AuthStatus {
        if let cached = cache.cachedStatus(includeToken: includeToken, now: now()) {
            return cached
        }

        do {
            return try fetchAuthStatus(
                includeToken: includeToken,
                refreshToken: false,
                allowCached: false
            )
        } catch {
            return try fetchAuthStatus(
                includeToken: includeToken,
                refreshToken: true,
                allowCached: false
            )
        }
    }

    func prewarmChatGPTStatus() throws {
        _ = try fetchAuthStatus(includeToken: true, refreshToken: true, allowCached: false)
    }

    private static func performLiveFetch(includeToken: Bool, refreshToken: Bool) throws -> AuthStatus {
        let executableURL = try Self.resolveExecutableURL()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let lineReader = JSONLineReader(fileHandle: stdoutPipe.fileHandleForReading)
        try process.run()
        defer {
            stdinPipe.fileHandleForWriting.closeFile()
            if process.isRunning {
                process.terminate()
            }
        }

        try Self.send(
            [
                "id": 0,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "chat_type",
                        "title": "ChatType",
                        "version": "0.1.1",
                    ],
                ],
            ],
            to: stdinPipe.fileHandleForWriting
        )

        let initializeResponse = try lineReader.waitForResponse(id: "0", timeout: 5)
        if let errorMessage = initializeResponse.errorMessage {
            throw CodexAuthError.initializeFailed(errorMessage)
        }

        try Self.send(
            [
                "method": "initialized",
                "params": [:],
            ],
            to: stdinPipe.fileHandleForWriting
        )

        try Self.send(
            [
                "id": "auth-status",
                "method": "getAuthStatus",
                "params": [
                    "includeToken": includeToken,
                    "refreshToken": refreshToken,
                ],
            ],
            to: stdinPipe.fileHandleForWriting
        )

        let authResponse = try lineReader.waitForResponse(id: "auth-status", timeout: 12)
        if let errorMessage = authResponse.errorMessage {
            throw CodexAuthError.authFailed(errorMessage)
        }

        guard
            let result = authResponse.result as? [String: Any],
            let authMethod = result["authMethod"] as? String
        else {
            throw CodexAuthError.malformedResponse
        }

        guard authMethod == "chatgpt" || authMethod == "chatgptAuthTokens" else {
            throw CodexAuthError.notChatGPT
        }

        let token = result["authToken"] as? String
        if includeToken, token?.isEmpty != false {
            throw CodexAuthError.missingToken
        }

        return AuthStatus(authMethod: authMethod, authToken: token)
    }

    static func resolveExecutableURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        for candidate in commandCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = String(directory) + "/codex"
                if fileManager.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }

        throw CodexAuthError.launcherNotFound
    }

    private static func send(_ payload: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        handle.write(data)
        handle.write(Data([0x0A]))
    }
}

private struct JSONRPCResponse {
    let id: String?
    let result: Any?
    let errorMessage: String?
}

private final class JSONLineReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [String: JSONRPCResponse] = [:]
    private let semaphore = DispatchSemaphore(value: 0)

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.fileHandle.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
    }

    deinit {
        fileHandle.readabilityHandler = nil
    }

    func waitForResponse(id: String, timeout: TimeInterval) throws -> JSONRPCResponse {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let response = takeResponse(id: id) {
                return response
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                break
            }
            _ = semaphore.wait(timeout: .now() + remaining)
        }

        throw CodexAuthError.timedOut(id)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }

        lock.lock()
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            parse(lineData)
        }
        lock.unlock()
    }

    private func parse(_ lineData: Data.SubSequence) {
        guard !lineData.isEmpty else { return }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(lineData)),
            let dictionary = object as? [String: Any]
        else {
            semaphore.signal()
            return
        }

        let idValue = dictionary["id"].map { String(describing: $0) }
        let errorMessage = ((dictionary["error"] as? [String: Any])?["message"] as? String)
        let response = JSONRPCResponse(
            id: idValue,
            result: dictionary["result"],
            errorMessage: errorMessage
        )

        if let idValue {
            responses[idValue] = response
        }
        semaphore.signal()
    }

    private func takeResponse(id: String) -> JSONRPCResponse? {
        lock.lock()
        defer { lock.unlock() }
        return responses.removeValue(forKey: id)
    }
}
