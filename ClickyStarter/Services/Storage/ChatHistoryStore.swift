import Foundation

actor ChatHistoryStore {
    // MARK: - Stored properties

    let directory: URL

    // MARK: - Computed properties

    var archiveURL: URL { directory.appending(path: "conversations.json") }

    // MARK: - Initializer

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "ClickyStarter")) {
        self.directory = directory
    }

    // MARK: - Functions

    func load() throws -> [Conversation] {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return [] }
        let data = try Data(contentsOf: archiveURL)
        return try JSONDecoder().decode([Conversation].self, from: data)
    }

    func save(_ conversations: [Conversation]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(conversations).write(to: archiveURL, options: .atomic)
    }

    func prepareWorkspace() throws -> URL {
        let workspace = directory.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }
}
