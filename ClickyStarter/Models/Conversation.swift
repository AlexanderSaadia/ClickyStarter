import Foundation

struct Conversation: Identifiable, Codable, Sendable, Equatable {
    // MARK: - Stored properties

    var id: UUID = UUID()
    var title: String = "New conversation"
    var threadID: String?
    var messages: [ChatMessage] = []
    var draft: String = ""
    var updatedAt: Date = .now
}
