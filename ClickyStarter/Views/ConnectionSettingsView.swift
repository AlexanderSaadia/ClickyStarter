import SwiftUI
import UniformTypeIdentifiers

struct ConnectionSettingsView: View {
    // MARK: - Stored properties

    @Bindable var model: ChatViewModel

    // MARK: - Computed properties

    var body: some View {
        Form {
            Section("Codex connection") {
                TextField("Executable", text: $model.executablePath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose executable…", action: chooseExecutable)
                LabeledContent("Status", value: model.status)
                LabeledContent("Model", value: model.modelName)
                Button("Reconnect") { Task { await model.connect() } }
                    .disabled(model.isConnecting || model.isWorking)
            }
            Section("About this prototype") {
                Text("Uses your existing Codex sign-in. Messages are sent through Codex to its configured AI provider. This version supports text chat; screen capture and voice come next.")
                Text("Chats are saved in Application Support/ClickyStarter. Codex also stores its conversation context in its own local history.")
                Button("Show saved chats") {
                    NSWorkspace.shared.open(URL.applicationSupportDirectory.appending(path: "ClickyStarter"))
                }
            }
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 540, height: 430)
    }

    // MARK: - Functions

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Codex executable"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = URL(filePath: model.executablePath).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { model.executablePath = url.path }
    }
}
