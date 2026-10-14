import SwiftUI

struct ChatView: View {
    // MARK: - Stored properties

    @Bindable var model: ChatViewModel

    // MARK: - Computed properties

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                Label("YOUR SPACE", systemImage: "sparkle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                Button("New conversation", systemImage: "square.and.pencil") { model.newConversation() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.horizontal, 12)
                    .disabled(model.isWorking)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.conversations) { conversation in
                            Button {
                                model.selectConversation(conversation.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(conversation.title)
                                        .font(.body.weight(.medium))
                                        .lineLimit(2)
                                    Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(model.selectedID == conversation.id ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isWorking)
                            .accessibilityAddTraits(model.selectedID == conversation.id ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 8)
                }
                Spacer(minLength: 0)
                SettingsLink {
                    Label("Connection settings", systemImage: "gearshape")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 300)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                if let errorMessage = model.errorMessage {
                    HStack(alignment: .top) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Dismiss", systemImage: "xmark") { model.errorMessage = nil }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(.orange.opacity(0.12))
                }
                if model.needsSignIn {
                    Button("Sign in with ChatGPT") {
                        Task {
                            if let url = await model.signIn() { NSWorkspace.shared.open(url) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                TranscriptView(messages: model.selectedConversation?.messages ?? [], isWorking: model.isWorking)
                ComposerView(model: model)
            }
            .background(.background)
            .navigationTitle("Clicky Starter")
        }
        .frame(minWidth: 720, minHeight: 500)
        .tint(.indigo)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.indigo)
                .padding(10)
                .background(.indigo.opacity(0.1), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("A little help, a little closer.")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isConnected ? .green : .orange)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.isConnected && !model.needsSignIn {
                Button("Reconnect", systemImage: "arrow.clockwise") { Task { await model.connect() } }
                    .disabled(model.isConnecting || model.isWorking)
            }
        }
        .padding(20)
    }
}
