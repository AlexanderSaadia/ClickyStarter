import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    // MARK: - Stored properties

    var conversations: [Conversation] = []
    var selectedID: UUID?
    var draft: String = ""
    var status: String = "Connecting…"
    var errorMessage: String?
    var isConnected: Bool = false
    var isConnecting: Bool = false
    var isWorking: Bool = false
    var isStopping: Bool = false
    var needsSignIn: Bool = false
    var executablePath: String
    var modelName: String = "Codex default"

    @ObservationIgnored private let client: any CodexServing
    @ObservationIgnored private let history: ChatHistoryStore
    @ObservationIgnored private var workspace: URL?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var stopWatchdog: Task<Void, Never>?
    @ObservationIgnored private var didStart: Bool = false
    @ObservationIgnored private var historyWritable: Bool = true
    @ObservationIgnored private var activeConversationID: UUID?
    @ObservationIgnored private var activeTurnID: String?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var interruptSent: Bool = false
    @ObservationIgnored private var resumedThreads: Set<String> = []
    @ObservationIgnored private var threadConfig: [String: JSONValue] = [:]

    // MARK: - Computed properties

    var selectedConversation: Conversation? {
        for conversation in conversations {
            if conversation.id == selectedID { return conversation }
        }
        return nil
    }

    var canSend: Bool {
        isConnected && !isWorking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initializer

    init(client: any CodexServing = CodexClient(), history: ChatHistoryStore = ChatHistoryStore()) {
        self.client = client
        self.history = history
        executablePath = UserDefaults.standard.string(forKey: "codexExecutablePath") ?? Self.findExecutable()
    }

    // MARK: - Functions

    static func findExecutable() -> String {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return candidates[0]
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        do {
            conversations = try await history.load()
        } catch {
            historyWritable = false
            errorMessage = "Saved chats could not be read. The original file has been preserved; this session will not overwrite it. \(error.localizedDescription)"
        }
        if conversations.isEmpty { newConversation() }
        else { selectConversation(conversations[0].id) }
        let events = client.events
        eventTask = Task { [weak self] in
            for await event in events {
                if Task.isCancelled { break }
                self?.handle(event)
            }
        }
        await connect()
    }

    func connect() async {
        guard !isConnecting, !isWorking else { return }
        isConnecting = true
        isConnected = false
        status = "Connecting…"
        defer { isConnecting = false }
        do {
            guard FileManager.default.isExecutableFile(atPath: executablePath) else {
                throw CodexError.message("Codex was not found. Open Settings and choose the Codex executable installed on your Mac.")
            }
            let directory = try await history.prepareWorkspace()
            workspace = directory
            try await client.start(executable: URL(filePath: executablePath), directory: directory)
            resumedThreads.removeAll()
            // Disable inherited MCP servers for this initial, conversation-only app.
            let configuration = try await client.request("config/read", params: .object(["includeLayers": .bool(false)]))
            var disabledServers: [String: JSONValue] = [:]
            for name in configuration["config"]["mcp_servers"].object.keys {
                disabledServers[name] = .object(["enabled": .bool(false)])
            }
            threadConfig = ["mcp_servers": .object(disabledServers)]
            let account = try await client.request("account/read", params: .object(["refreshToken": .bool(false)]))
            needsSignIn = account["account"] == .null && account["requiresOpenaiAuth"] == .bool(true)
            isConnected = !needsSignIn
            status = needsSignIn ? "Sign in to Codex" : "Ready"
            UserDefaults.standard.set(executablePath, forKey: "codexExecutablePath")
        } catch {
            await client.disconnect()
            status = "Disconnected"
            errorMessage = error.localizedDescription
        }
    }

    func signIn() async -> URL? {
        do {
            let response = try await client.request("account/login/start", params: .object(["type": .string("chatgpt")]))
            guard let address = response["authUrl"].string, let url = URL(string: address), url.scheme == "https" else {
                throw CodexError.message("Codex did not return a valid sign-in page. Try reconnecting.")
            }
            status = "Finish signing in in your browser"
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func newConversation() {
        guard !isWorking else { return }
        rememberDraft()
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
        draft = ""
        scheduleSave()
    }

    func selectConversation(_ id: UUID) {
        guard !isWorking else { return }
        rememberDraft()
        selectedID = id
        draft = selectedConversation?.draft ?? ""
    }

    func rememberDraft() {
        guard let index = indexOf(selectedID) else { return }
        conversations[index].draft = draft
        scheduleSave()
    }

    func send() async {
        guard canSend, let conversationID = selectedID, let index = indexOf(conversationID) else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        conversations[index].draft = ""
        if conversations[index].messages.isEmpty { conversations[index].title = String(text.prefix(48)) }
        conversations[index].messages.append(ChatMessage(role: "user", text: text))
        conversations[index].updatedAt = .now
        isWorking = true
        isStopping = false
        interruptSent = false
        activeConversationID = conversationID
        activeTurnID = nil
        let operation = UUID()
        operationID = operation
        errorMessage = nil
        status = "Starting…"
        await flushHistory()
        do {
            let threadID = try await prepareThread(conversationID)
            guard operationID == operation else { return }
            if isStopping {
                finish(note: "Stopped before sending to Codex.")
                return
            }
            status = "Thinking…"
            let result = try await client.request("turn/start", params: .object([
                "threadId": .string(threadID),
                "input": .array([.object(["type": .string("text"), "text": .string(text)])])
            ]))
            guard operationID == operation else { return }
            guard let turnID = result["turn"]["id"].string else {
                throw CodexError.message("Codex did not return a response identifier.")
            }
            activeTurnID = turnID
            if isStopping { await interrupt() }
        } catch {
            guard operationID == operation else { return }
            errorMessage = error.localizedDescription
            finish(note: "The response failed. \(error.localizedDescription)")
        }
    }

    func stop() async {
        guard isWorking, !isStopping else { return }
        isStopping = true
        status = "Stopping…"
        let operation = operationID
        stopWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) }
            catch { return }
            guard let self, self.operationID == operation, self.isWorking else { return }
            await self.client.disconnect()
            self.isConnected = false
            self.finish(note: "Stopped by closing the connection. Reconnect to continue.")
        }
        await interrupt()
    }

    func shutdown() async {
        if isWorking { finish(note: "Interrupted when the app closed.") }
        rememberDraft()
        await flushHistory()
        await client.disconnect()
        eventTask?.cancel()
    }

    func flushHistory() async {
        saveTask?.cancel()
        guard historyWritable else { return }
        do { try await history.save(conversations) }
        catch { errorMessage = "Could not save your chats: \(error.localizedDescription)" }
    }

    private func prepareThread(_ conversationID: UUID) async throws -> String {
        guard let index = indexOf(conversationID), let workspace else {
            throw CodexError.message("The conversation is unavailable.")
        }
        var params: [String: JSONValue] = [
            "cwd": .string(workspace.path),
            "sandbox": .string("read-only"),
            "approvalPolicy": .string("never"),
            "config": .object(threadConfig),
            "baseInstructions": .string("You are a friendly personal assistant in Clicky Starter, a native Mac chat app. Answer clearly and concisely. This first version supports text conversation only. Do not use tools, access files or accounts, execute commands, or claim to see the screen. Respond directly using the conversation. Be honest about uncertainty.")
        ]
        if let threadID = conversations[index].threadID {
            if !resumedThreads.contains(threadID) {
                params["threadId"] = .string(threadID)
                _ = try await client.request("thread/resume", params: .object(params))
                resumedThreads.insert(threadID)
            }
            return threadID
        }
        let response = try await client.request("thread/start", params: .object(params))
        guard let threadID = response["thread"]["id"].string else {
            throw CodexError.message("Codex could not create a conversation.")
        }
        conversations[index].threadID = threadID
        if let model = response["model"].string { modelName = model }
        resumedThreads.insert(threadID)
        await flushHistory()
        return threadID
    }

    private func interrupt() async {
        guard !interruptSent, let turnID = activeTurnID,
              let index = indexOf(activeConversationID), let threadID = conversations[index].threadID else { return }
        interruptSent = true
        do {
            _ = try await client.request("turn/interrupt", params: .object([
                "threadId": .string(threadID), "turnId": .string(turnID)
            ]))
        } catch {
            guard isWorking else { return }
            errorMessage = "Could not interrupt normally. Closing the connection."
            await client.disconnect()
            isConnected = false
            finish(note: "Stopped by closing the connection.")
        }
    }

    func handle(_ event: JSONValue) {
        guard let method = event["method"].string else { return }
        let params = event["params"]
        if method == "client/disconnected" {
            isConnected = false
            errorMessage = params["message"].string
            if isWorking { finish(note: "The connection was interrupted.") }
            status = "Disconnected"
            return
        }
        if method == "account/login/completed" {
            if params["success"] == .bool(true) {
                needsSignIn = false
                isConnected = true
                status = "Ready"
            } else { errorMessage = params["error"].string ?? "Sign-in was not completed." }
            return
        }
        guard isWorking, let index = indexOf(activeConversationID),
              params["threadId"].string == conversations[index].threadID else { return }
        let eventTurnID = params["turnId"].string ?? params["turn"]["id"].string
        if let activeTurnID, let eventTurnID, activeTurnID != eventTurnID { return }
        switch method {
        case "turn/started":
            activeTurnID = params["turn"]["id"].string
            if isStopping { Task { await interrupt() } }
        case "item/agentMessage/delta":
            guard let itemID = params["itemId"].string, let delta = params["delta"].string else { return }
            updateMessage(index: index, itemID: itemID, text: delta, replace: false)
            if !isStopping { status = "Replying…" }
        case "item/completed":
            let item = params["item"]
            if item["type"].string == "agentMessage", let itemID = item["id"].string {
                updateMessage(index: index, itemID: itemID, text: item["text"].string ?? "", replace: true)
            }
        case "turn/completed":
            let turn = params["turn"]
            for item in turn["items"].array {
                if item["type"].string == "agentMessage", let itemID = item["id"].string {
                    updateMessage(index: index, itemID: itemID, text: item["text"].string ?? "", replace: true)
                }
            }
            switch turn["status"].string {
            case "completed": finish(note: nil)
            case "interrupted": finish(note: "Response stopped.")
            default:
                let message = turn["error"]["message"].string ?? "The response did not complete."
                errorMessage = message
                finish(note: message)
            }
        case "error":
            if params["willRetry"] == .bool(true) { status = "Reconnecting to the model…" }
            else { errorMessage = params["error"]["message"].string ?? "Codex reported an error." }
        default: break
        }
    }

    private func updateMessage(index: Int, itemID: String, text: String, replace: Bool) {
        for messageIndex in conversations[index].messages.indices {
            if conversations[index].messages[messageIndex].itemID == itemID {
                if replace { conversations[index].messages[messageIndex].text = text }
                else { conversations[index].messages[messageIndex].text += text }
                scheduleSave()
                return
            }
        }
        conversations[index].messages.append(ChatMessage(role: "assistant", text: text, itemID: itemID))
        scheduleSave()
    }

    private func finish(note: String?) {
        if let note, let index = indexOf(activeConversationID) {
            conversations[index].messages.append(ChatMessage(role: "notice", text: note))
        }
        isWorking = false
        isStopping = false
        activeTurnID = nil
        activeConversationID = nil
        operationID = nil
        stopWatchdog?.cancel()
        stopWatchdog = nil
        status = isConnected ? "Ready" : "Disconnected"
        scheduleSave()
    }

    private func indexOf(_ id: UUID?) -> Int? {
        for index in conversations.indices {
            if conversations[index].id == id { return index }
        }
        return nil
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            await self?.flushHistory()
        }
    }
}
