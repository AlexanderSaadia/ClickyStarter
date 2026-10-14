import Foundation

protocol CodexServing: Sendable {
    var events: AsyncStream<JSONValue> { get }
    func start(executable: URL, directory: URL) async throws
    func request(_ method: String, params: JSONValue) async throws -> JSONValue
    func disconnect() async
}
