import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Stored properties

    var model: ChatViewModel?
    private var isTerminating: Bool = false

    // MARK: - Functions

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task {
            await model?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
