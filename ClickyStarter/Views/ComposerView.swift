import SwiftUI

struct ComposerView: View {
    // MARK: - Stored properties

    @Bindable var model: ChatViewModel
    @FocusState private var isFocused: Bool

    // MARK: - Computed properties

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 12) {
                TextField("Message Clicky…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...6)
                    .focused($isFocused)
                    .accessibilityLabel("Message")
                    .onChange(of: model.draft) { model.rememberDraft() }
                HStack {
                    Text("⌘ Return to send")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isWorking {
                        Button(model.isStopping ? "Stopping…" : "Stop", systemImage: "stop.fill") {
                            Task { await model.stop() }
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                        .disabled(model.isStopping)
                        .buttonStyle(.bordered)
                    } else {
                        Button("Send", systemImage: "arrow.up") { Task { await model.send() } }
                            .keyboardShortcut(.return, modifiers: .command)
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canSend)
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 16))
            Text("Powered by your Codex connection · Text chat")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .padding(.top, 8)
        .onAppear { isFocused = true }
    }
}
