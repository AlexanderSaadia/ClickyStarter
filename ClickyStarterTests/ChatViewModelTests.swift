import XCTest
@testable import ClickyStarter

@MainActor
final class ChatViewModelTests: XCTestCase {
    // MARK: - Functions

    private func temporaryHistory() -> ChatHistoryStore {
        ChatHistoryStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    private func event(_ method: String, fields: [String: JSONValue]) -> JSONValue {
        var params = fields
        params["threadId"] = .string("test-thread")
        params["turnId"] = .string("test-turn")
        return .object(["method": .string(method), "params": .object(params)])
    }

    func testStreamingFinalMessageDoesNotDuplicateAndPersists() async throws {
        let client = MockCodexClient()
        let history = temporaryHistory()
        let model = ChatViewModel(client: client, history: history)
        await model.start()
        model.draft = "Hello"
        await model.send()
        model.handle(event("item/agentMessage/delta", fields: ["itemId": .string("answer"), "delta": .string("Hel")]))
        model.handle(event("item/agentMessage/delta", fields: ["itemId": .string("answer"), "delta": .string("lo!")]))
        model.handle(event("item/completed", fields: ["item": .object(["id": .string("answer"), "type": .string("agentMessage"), "text": .string("Hello!")])]))
        model.handle(event("turn/completed", fields: ["turn": .object(["id": .string("test-turn"), "status": .string("completed"), "items": .array([])])]))
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.selectedConversation?.messages.count, 2)
        XCTAssertEqual(model.selectedConversation?.messages.last?.text, "Hello!")
        await model.flushHistory()
        let saved = try await history.load()
        XCTAssertEqual(saved.first?.messages.last?.text, "Hello!")
        await model.shutdown()
    }

    func testStopWaitsForInterruptCompletionAndKeepsPartialReply() async {
        let client = MockCodexClient()
        let model = ChatViewModel(client: client, history: temporaryHistory())
        await model.start()
        model.draft = "Explain something"
        await model.send()
        model.handle(event("item/agentMessage/delta", fields: ["itemId": .string("answer"), "delta": .string("Partial answer")]))
        await model.stop()
        XCTAssertTrue(model.isStopping)
        XCTAssertTrue(model.isWorking)
        let methods = await client.methods
        XCTAssertTrue(methods.contains("turn/interrupt"))
        model.handle(event("turn/completed", fields: ["turn": .object(["id": .string("test-turn"), "status": .string("interrupted"), "items": .array([])])]))
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.selectedConversation?.messages[1].text, "Partial answer")
        XCTAssertEqual(model.selectedConversation?.messages.last?.text, "Response stopped.")
        await model.shutdown()
    }

    func testStopBeforeTurnIDArrivesStillInterrupts() async throws {
        let client = MockCodexClient()
        await client.delayTurn()
        let model = ChatViewModel(client: client, history: temporaryHistory())
        await model.start()
        model.draft = "A response"
        let sending = Task { await model.send() }
        for _ in 0..<200 {
            if await client.methods.contains("turn/start") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await model.stop()
        await client.releaseTurn()
        await sending.value
        let methods = await client.methods
        XCTAssertTrue(methods.contains("turn/interrupt"))
        await model.shutdown()
    }

    func testSavedConversationResumesOriginalThread() async throws {
        let history = temporaryHistory()
        let original = Conversation(title: "Earlier chat", threadID: "saved-thread", messages: [ChatMessage(role: "user", text: "Remember blue")])
        try await history.save([original])
        let client = MockCodexClient()
        let model = ChatViewModel(client: client, history: history)
        await model.start()
        model.draft = "Which color?"
        await model.send()
        let methods = await client.methods
        XCTAssertTrue(methods.contains("thread/resume"))
        XCTAssertFalse(methods.contains("thread/start"))
        XCTAssertEqual(model.selectedConversation?.threadID, "saved-thread")
        await model.shutdown()
    }

    func testCorruptHistoryIsPreserved() async throws {
        let history = temporaryHistory()
        let directory = await history.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("broken archive".utf8)
        let archive = directory.appending(path: "conversations.json")
        try original.write(to: archive)
        let model = ChatViewModel(client: MockCodexClient(), history: history)
        await model.start()
        XCTAssertNotNil(model.errorMessage)
        await model.flushHistory()
        XCTAssertEqual(try Data(contentsOf: archive), original)
        await model.shutdown()
    }

    func testFailedTurnReturnsToReadyAndShowsError() async {
        let model = ChatViewModel(client: MockCodexClient(), history: temporaryHistory())
        await model.start()
        model.draft = "Hi"
        await model.send()
        model.handle(event("turn/completed", fields: ["turn": .object([
            "id": .string("test-turn"), "status": .string("failed"),
            "error": .object(["message": .string("Usage limit reached")]), "items": .array([])
        ])]))
        XCTAssertFalse(model.isWorking)
        XCTAssertEqual(model.errorMessage, "Usage limit reached")
        await model.shutdown()
    }
}
