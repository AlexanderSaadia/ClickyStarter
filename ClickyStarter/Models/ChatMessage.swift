import Foundation

struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    // MARK: - Stored properties

    var id: UUID = UUID()
    var role: String
    var text: String
    var itemID: String?
    var date: Date = .now
}
