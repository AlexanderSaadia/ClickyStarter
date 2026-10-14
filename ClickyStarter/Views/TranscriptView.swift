import SwiftUI

struct TranscriptView: View {
    // MARK: - Stored properties

    let messages: [ChatMessage]
    let isWorking: Bool
    @State private var followsLatest: Bool = true

    // MARK: - Computed properties

    var body: some View {
        if messages.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                Text("What’s on your mind?")
                    .font(.title2.weight(.semibold))
                Text("Think through an idea, ask a question, or make a plan.\nYour conversations are saved on this Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(messages) { message in
                            MessageRow(message: message)
                        }
                        if isWorking {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Working on your reply…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Color.clear.frame(height: 1)
                            .id("latest")
                            .onAppear { followsLatest = true }
                            .onDisappear { followsLatest = false }
                    }
                    .padding(24)
                    .frame(maxWidth: 800, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages) {
                    if followsLatest { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest {
                        Button("Latest", systemImage: "arrow.down") {
                            followsLatest = true
                            proxy.scrollTo("latest", anchor: .bottom)
                        }
                        .buttonStyle(.bordered)
                        .padding()
                    }
                }
            }
        }
    }
}
