import Foundation

/// An opt-in integration check. Sends three small test prompts using the local Codex account.
@main
struct ConnectionSmokeCheck {
    // MARK: - Functions

    static func main() async throws {
        let client = CodexClient()
        let executable = URL(filePath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        let directory = FileManager.default.temporaryDirectory.appending(path: "ClickyStarterConnectionCheck")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try await client.start(executable: executable, directory: directory)
            let account = try await client.request("account/read", params: .object(["refreshToken": .bool(false)]))
            guard account["account"] != .null else { throw CodexError.message("No Codex account is signed in.") }
            print("PASS: initialized and authenticated")
            let configuration = try await client.request("config/read", params: .object(["includeLayers": .bool(false)]))
            var servers: [String: JSONValue] = [:]
            for name in configuration["config"]["mcp_servers"].object.keys {
                servers[name] = .object(["enabled": .bool(false)])
            }
            var threadParams: [String: JSONValue] = [
                "cwd": .string(directory.path), "sandbox": .string("read-only"), "approvalPolicy": .string("never"),
                "config": .object(["mcp_servers": .object(servers)]),
                "baseInstructions": .string("You are a text-only test assistant. Do not use tools. Follow the requested response format exactly.")
            ]
            let thread = try await client.request("thread/start", params: .object(threadParams))
            guard let threadID = thread["thread"]["id"].string else { throw CodexError.message("No thread ID.") }
            let first = try await runTurn(client: client, threadID: threadID, text: "Remember the word marigold. Reply with just READY.", interrupt: false)
            guard first.contains("READY") else { throw CodexError.message("The first response did not match.") }
            print("PASS: live reply received")
            await client.disconnect()
            try await client.start(executable: executable, directory: directory)
            threadParams["threadId"] = .string(threadID)
            _ = try await client.request("thread/resume", params: .object(threadParams))
            let second = try await runTurn(client: client, threadID: threadID, text: "What word did I ask you to remember? Reply with just that word.", interrupt: false)
            guard second.lowercased().contains("marigold") else { throw CodexError.message("Resumed context was missing.") }
            print("PASS: context survived disconnect and resume")
            _ = try await runTurn(client: client, threadID: threadID, text: "Write the numbers 1 to 2000, one per line. Continue until 2000.", interrupt: true)
            print("PASS: streaming response interrupted by turn/interrupt")
            await client.disconnect()
        } catch {
            await client.disconnect()
            throw error
        }
    }

    static func runTurn(client: CodexClient, threadID: String, text: String, interrupt: Bool) async throws -> String {
        let response = try await client.request("turn/start", params: .object([
            "threadId": .string(threadID),
            "input": .array([.object(["type": .string("text"), "text": .string(text)])])
        ]))
        guard let turnID = response["turn"]["id"].string else { throw CodexError.message("No turn ID.") }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var output = ""
                var sentInterrupt = false
                for await event in client.events {
                    let method = event["method"].string
                    let params = event["params"]
                    if method == "client/disconnected" { throw CodexError.message("Disconnected during turn.") }
                    guard params["threadId"].string == threadID else { continue }
                    if method == "item/agentMessage/delta", params["turnId"].string == turnID {
                        output += params["delta"].string ?? ""
                        if interrupt && !sentInterrupt {
                            sentInterrupt = true
                            _ = try await client.request("turn/interrupt", params: .object([
                                "threadId": .string(threadID), "turnId": .string(turnID)
                            ]))
                        }
                    }
                    if method == "turn/completed", params["turn"]["id"].string == turnID {
                        let expected = interrupt ? "interrupted" : "completed"
                        guard params["turn"]["status"].string == expected else {
                            throw CodexError.message("Unexpected completion: \(params["turn"]["status"].string ?? "unknown"). \(params["turn"]["error"]["message"].string ?? "")")
                        }
                        return output
                    }
                }
                throw CodexError.message("The event stream ended.")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(45))
                throw CodexError.message("Live reply timed out.")
            }
            defer { group.cancelAll() }
            return try await group.next() ?? ""
        }
    }
}
