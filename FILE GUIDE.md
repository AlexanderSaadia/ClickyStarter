# What each app file does

Open **ClickyStarter.xcodeproj** in Xcode. This is the working **macOS** app. The playgrounds in the Desktop hub are separate learning exercises.

| File inside the project | Purpose |
| --- | --- |
| ClickyStarter/ClickyStarterApp.swift | Starts the app, creates shared state, and opens chat and Settings windows. |
| ClickyStarter/AppDelegate.swift | Saves chats and closes the Codex connection when you quit. |
| ClickyStarter/Views/ChatView.swift | Main window, conversation sidebar, connection status and errors. |
| ClickyStarter/Views/TranscriptView.swift | Scrollable history and jump-to-latest control. |
| ClickyStarter/Views/MessageRow.swift | How an individual message looks. |
| ClickyStarter/Views/ComposerView.swift | Message input, Send, Stop and keyboard shortcuts. |
| ClickyStarter/Views/ConnectionSettingsView.swift | Codex executable selection and connection settings. |
| ClickyStarter/Models/ChatModel.swift | Coordinates sending, streaming, stopping, history and connection state. |
| ClickyStarter/Models/Conversation.swift | A conversation's title, messages, draft and Codex thread identifier. |
| ClickyStarter/Models/ChatMessage.swift | One message's text, author, date and identifiers. |
| ClickyStarter/Models/JSONValue.swift | Represents the JSON messages exchanged with Codex. |
| ClickyStarter/Services/CodexClient.swift | Starts Codex, sends protocol requests and receives responses. |
| ClickyStarter/Services/CodexServing.swift | Connection interface used by the real client and test client, plus connection errors. |
| ClickyStarter/Services/ChatHistoryStore.swift | Reads and atomically saves conversations on this Mac. |
| ClickyStarterTests/ChatModelTests.swift | Tests streaming, stopping, resumed context, errors and damaged history files. |
| ClickyStarterTests/MockCodexClient.swift | Simulates Codex so normal tests send no live prompts. |
| Support/ConnectionSmokeCheck.swift | Optional live connection/resume/cancellation check; uses the Codex account's allowance. |
| Support/create_project.py | Regenerates the Xcode project from its Swift files. |
| README.md | Running instructions and verification details. |
| .build/ | Generated build output, not source code to edit. |
| .git/ | Local version-control data. |

The Swift filenames already match their types and responsibilities, so they remain stable. Start with **ChatView.swift** for appearance, **ChatModel.swift** for chat behavior, and **CodexClient.swift** for the engine connection.

Saved chats live separately in `~/Library/Application Support/ClickyStarter`. They are personal app data, not files to move when organizing the project.
