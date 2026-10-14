import Foundation
@testable import ClickyStarter

actor MockCodexClient: CodexServing {
    // MARK: - Stored properties

    nonisolated let events: AsyncStream<JSONValue>
    private let continuation: AsyncStream<JSONValue>.Continuation
    private(set) var methods: [String] = []
    private(set) var disconnected: Bool = false
    var delayedTurn: CheckedContinuation<JSONValue, Never>?
    var delayTurnResponse: Bool = false

    // MARK: - Initializer

    init() {
        let stream = AsyncStream<JSONValue>.makeStream()
        events = stream.stream
        continuation = stream.continuation
    }

    // MARK: - Functions

    func start(executable: URL, directory: URL) async throws {}

    func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        methods.append(method)
        switch method {
        case "account/read": return .object(["account": .object(["type": .string("chatgpt")])])
        case "config/read": return .object(["config": .object([:])])
        case "thread/start": return .object(["thread": .object(["id": .string("test-thread")])])
        case "turn/start":
            if delayTurnResponse {
                return await withCheckedContinuation { savedContinuation in delayedTurn = savedContinuation }
            }
            return .object(["turn": .object(["id": .string("test-turn")])])
        default: return .object([:])
        }
    }

    func disconnect() { disconnected = true }

    func delayTurn() { delayTurnResponse = true }

    func releaseTurn() {
        delayedTurn?.resume(returning: .object(["turn": .object(["id": .string("test-turn")])]))
        delayedTurn = nil
    }
}
