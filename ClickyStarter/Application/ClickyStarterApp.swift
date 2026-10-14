import SwiftUI

@main
struct ClickyStarterApp: App {
    // MARK: - Stored properties

    @State private var model = ChatViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Computed properties

    var body: some Scene {
        Window("Clicky Starter", id: "main") {
            ChatView(model: model)
                .task {
                    appDelegate.model = model
                    if NSClassFromString("XCTestCase") == nil { await model.start() }
                }
        }
        .defaultSize(width: 940, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation", systemImage: "square.and.pencil") { model.newConversation() }
                    .keyboardShortcut("n")
                    .disabled(model.isWorking)
            }
        }

        Settings {
            ConnectionSettingsView(model: model)
        }
    }
}
    
