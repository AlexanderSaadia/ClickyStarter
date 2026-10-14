# Clicky Starter

A personal, native macOS chat app built with SwiftUI, Observation and the installed Codex app-server. Requires macOS 14 or newer and Xcode 26 or newer. No third-party Swift packages.

## Run in Xcode

1. Open `ClickyStarter.xcodeproj`.
2. Select the **ClickyStarter** scheme and **My Mac**.
3. Press **Command–R**.
4. Wait for **Ready**, type a message, then press **Command–Return**.
5. Use **Stop** or **Escape** to interrupt a response. **Command–N** starts a new conversation.

The executable is detected in the ChatGPT/Codex app bundle or common Homebrew locations. If necessary, choose it in **Clicky Starter → Settings**. The app uses the existing Codex authentication state; if none exists, it offers Codex's browser sign-in flow. It never reads or displays authentication tokens. Account/model limits still apply.

## What is implemented

- Native sidebar and conversation window, selectable responses, multiline composer.
- Dedicated local Codex app-server child process using newline-delimited JSON over stdin/stdout.
- Initialization, account status, browser sign-in, new threads and resumed threads.
- Streaming assistant messages and authoritative final-message reconciliation.
- Real `turn/interrupt`, including Stop during startup; an eight-second stop fallback closes this app's connection.
- Atomic JSON chat persistence, per-conversation drafts, preserved corrupt archives, connection/error states and graceful quit.

This is a local development app. It runs without the macOS App Sandbox so it can launch the existing Codex executable and use its authentication storage. Codex threads use its separate read-only execution sandbox. Shell, browser, computer, apps, plugins, hooks and multi-agent features are disabled for this chat milestone; configured MCP servers are disabled on its threads. Unhandled server requests are rejected. It is not a production-distribution or App Store configuration.

## Project layout

- `Models/ChatModel.swift`: observable UI state, response lifecycle, history and stop handling.
- `Services/CodexClient.swift`: process ownership, protocol requests, notifications and timeouts.
- `Services/ChatHistoryStore.swift`: local history persistence.
- `Views/`: chat window, messages, composer and connection settings.
- `ClickyStarterTests/`: lifecycle and persistence tests.

The app saves display history under `~/Library/Application Support/ClickyStarter/conversations.json`. Codex maintains the underlying threads in its own data directory. This app lists only conversations it creates. It does not import your other Codex chats. Thread identifiers connect display history to Codex context.

Protocol reference: https://learn.chatgpt.com/docs/app-server

## Verification completed

Validated locally with Xcode 26.4.1 and Codex CLI 0.153.4:

- Debug build succeeded for this Apple Silicon Mac.
- Six automated tests passed: streamed/final text reconciliation, cancellation, cancellation before the turn ID arrives, thread resume, corrupt archive preservation, and failed-turn recovery.
- An opt-in live check using the production client received a reply, remembered context across a process restart, and interrupted a streaming response.
- The running app was checked through its interface: sending, receiving, Stop, quitting, reopening saved history, and starting a fresh conversation all worked.

`Support/ConnectionSmokeCheck.swift` is a developer-only integration check, excluded from the app target. It sends real prompts and uses your Codex allowance. The normal unit tests use a mock connection and send no prompts.

## Next milestones

Screen context, push-to-talk voice, a floating companion and controlled task tools can be added independently after the text-chat foundation is verified.
