import SwiftUI

struct MessageRow: View {
    // MARK: - Stored properties

    let message: ChatMessage

    // MARK: - Computed properties

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if message.role != "notice" {
                Text(message.role == "user" ? "YOU" : "CLICKY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(message.role == "user" ? .secondary : Color.indigo)
            }
            Text(message.text)
                .font(message.role == "notice" ? .callout : .body)
                .foregroundStyle(message.role == "notice" ? .secondary : .primary)
                .textSelection(.enabled)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(message.role == "user" ? 16 : 0)
        .background(message.role == "user" ? Color.primary.opacity(0.04) : .clear, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
