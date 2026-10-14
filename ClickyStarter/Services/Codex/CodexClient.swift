import Foundation

actor CodexClient: CodexServing {
    // MARK: - Stored properties

    nonisolated let events: AsyncStream<JSONValue>
    private let eventContinuation: AsyncStream<JSONValue>.Continuation
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputTask: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var nextID: Int = 0
    private var generation: UUID = UUID()

    // MARK: - Initializer

    init() {
        let stream = AsyncStream<JSONValue>.makeStream()
        events = stream.stream
        eventContinuation = stream.continuation
    }

    // MARK: - Functions

    func start(executable: URL, directory: URL) async throws {
        disconnect()
        let connectionID = UUID()
        generation = connectionID
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = executable
        child.currentDirectoryURL = directory
        child.arguments = [
            "app-server", "--listen", "stdio://",
            "-c", "sandbox_mode=\"read-only\"",
            "-c", "approval_policy=\"never\"",
            "-c", "web_search=\"disabled\"",
            "--disable", "shell_tool", "--disable", "apps",
            "--disable", "plugins", "--disable", "browser_use",
            "--disable", "computer_use", "--disable", "multi_agent",
            "--disable", "hooks"
        ]
        var environment = ProcessInfo.processInfo.environment
        // A Finder-launched app does not inherit a terminal's PATH.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        child.environment = environment
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] terminated in
            let status = terminated.terminationStatus
            Task { await self?.processEnded(connectionID: connectionID, status: status) }
        }
        try child.run()
        process = child
        inputHandle = input.fileHandleForWriting
        let outputHandle = output.fileHandleForReading
        outputTask = Task { [weak self] in
            do {
                for try await line in outputHandle.bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8) else { continue }
                    let message = try JSONDecoder().decode(JSONValue.self, from: data)
                    await self?.receive(message, connectionID: connectionID)
                }
            } catch {
                await self?.readFailed(connectionID: connectionID)
            }
        }
        do {
            _ = try await request("initialize", params: .object([
                "clientInfo": .object([
                    "name": .string("clicky_starter"),
                    "title": .string("Clicky Starter"),
                    "version": .string("0.1.0")
                ])
            ]))
            try write(.object(["method": .string("initialized"), "params": .object([:])]))
        } catch {
            disconnect()
            throw error
        }
    }

    func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        guard process?.isRunning == true else {
            throw CodexError.message("Codex is disconnected. Choose Reconnect to try again.")
        }
        nextID += 1
        let requestID = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
            do {
                try write(.object([
                    "id": .number(Double(requestID)),
                    "method": .string(method),
                    "params": params
                ]))
                timeouts[requestID] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { return }
                    await self?.expire(requestID)
                }
            } catch {
                pending.removeValue(forKey: requestID)?.resume(throwing: error)
            }
        }
    }

    func disconnect() {
        generation = UUID()
        outputTask?.cancel()
        outputTask = nil
        try? inputHandle?.close()
        inputHandle = nil
        if let child = process, child.isRunning { child.terminate() }
        process = nil
        failPending("The Codex connection closed.")
    }

    private func write(_ message: JSONValue) throws {
        guard let inputHandle else { throw CodexError.message("Codex is not connected.") }
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func receive(_ message: JSONValue, connectionID: UUID) {
        guard generation == connectionID else { return }
        if message["method"].string != nil {
            if message["id"] != .null {
                // This chat-only milestone never approves tool execution requests.
                do {
                    try write(.object([
                        "id": message["id"],
                        "error": .object([
                            "code": .number(-32601),
                            "message": .string("This chat client does not support tool approval or interaction requests.")
                        ])
                    ]))
                } catch { readFailed(connectionID: connectionID) }
            } else {
                eventContinuation.yield(message)
            }
            return
        }
        guard let requestID = message["id"].integer,
              let continuation = pending.removeValue(forKey: requestID) else { return }
        timeouts.removeValue(forKey: requestID)?.cancel()
        if message["error"] != .null {
            continuation.resume(throwing: CodexError.message(message["error"]["message"].string ?? "Codex reported an error."))
        } else {
            continuation.resume(returning: message["result"])
        }
    }

    private func expire(_ requestID: Int) {
        timeouts.removeValue(forKey: requestID)
        pending.removeValue(forKey: requestID)?.resume(throwing: CodexError.message("Codex did not respond within 30 seconds. Reconnect and try again."))
    }

    private func failPending(_ message: String) {
        for timeout in timeouts.values { timeout.cancel() }
        timeouts.removeAll()
        let requests = pending
        pending.removeAll()
        for continuation in requests.values {
            continuation.resume(throwing: CodexError.message(message))
        }
    }

    private func processEnded(connectionID: UUID, status: Int32) {
        guard generation == connectionID else { return }
        disconnect()
        eventContinuation.yield(.object([
            "method": .string("client/disconnected"),
            "params": .object(["message": .string("Codex closed (status \(status)). Choose Reconnect.")])
        ]))
    }

    private func readFailed(connectionID: UUID) {
        guard generation == connectionID else { return }
        disconnect()
        eventContinuation.yield(.object([
            "method": .string("client/disconnected"),
            "params": .object(["message": .string("The Codex response could not be read. Choose Reconnect.")])
        ]))
    }
}
