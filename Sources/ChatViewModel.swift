import SwiftUI
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    let store = ConversationStore()
    let engine = ChatEngine()
    let settings = SettingsStore()

    @Published var currentID: UUID
    @Published var input = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var streamingID: UUID?

    private var task: Task<Void, Never>?
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    init() {
        if let latest = store.conversations.max(by: { $0.updatedAt < $1.updatedAt }) {
            currentID = latest.id
        } else {
            let c = Conversation()
            store.conversations.append(c)
            currentID = c.id
        }
    }

    // MARK: access

    var current: Conversation {
        store.conversations.first { $0.id == currentID } ?? Conversation()
    }

    var sortedConversations: [Conversation] {
        store.conversations.filter { !$0.messages.isEmpty || $0.id == currentID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: conversations

    func newChat() {
        stop()
        if let i = store.index(of: currentID), store.conversations[i].messages.isEmpty { return }   // already on an empty chat
        let c = Conversation()
        store.conversations.append(c)
        currentID = c.id
        engine.invalidate()
    }

    func select(_ id: UUID) {
        guard id != currentID else { return }
        stop()
        currentID = id
        engine.invalidate()
    }

    func delete(_ id: UUID) {
        if id == currentID { stop() }
        store.conversations.removeAll { $0.id == id }
        if store.conversations.isEmpty || id == currentID {
            if let next = store.conversations.max(by: { $0.updatedAt < $1.updatedAt }) { currentID = next.id }
            else { let c = Conversation(); store.conversations.append(c); currentID = c.id }
            engine.invalidate()
        }
        store.save()
    }

    func deleteAll() {
        stop()
        store.conversations.removeAll()
        let c = Conversation()
        store.conversations.append(c)
        currentID = c.id
        engine.invalidate()
        store.save()
    }

    // MARK: sending

    func prewarm() { engine.prewarm(conversationID: currentID, history: current.messages, settings: settings.chatSettings) }

    func send(_ text: String? = nil) {
        let prompt = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating, engine.status.isReady, let ci = store.index(of: currentID) else { return }
        input = ""
        let history = store.conversations[ci].messages
        if history.isEmpty { store.conversations[ci].title = ChatLogic.title(from: prompt) }
        store.conversations[ci].messages.append(ChatMessage(role: .user, text: prompt))
        generate(prompt: prompt, history: history)
    }

    /// Regenerate the last answer (or retry after an error).
    func regenerate() {
        guard !isGenerating, let ci = store.index(of: currentID) else { return }
        var msgs = store.conversations[ci].messages
        while let last = msgs.last, last.role == .assistant { msgs.removeLast() }
        guard let lastUser = msgs.last, lastUser.role == .user else { return }
        store.conversations[ci].messages = msgs
        engine.invalidate()
        generate(prompt: lastUser.text, history: Array(msgs.dropLast()))
    }

    private func generate(prompt: String, history: [ChatMessage]) {
        guard let ci = store.index(of: currentID) else { return }
        let convoID = currentID
        let placeholder = ChatMessage(role: .assistant, text: "")
        store.conversations[ci].messages.append(placeholder)
        store.conversations[ci].updatedAt = Date()
        streamingID = placeholder.id
        isGenerating = true
        if settings.haptics { impact.impactOccurred() }
        let chatSettings = settings.chatSettings
        task = Task { [weak self] in
            guard let self else { return }
            var failure: Error?
            do {
                _ = try await self.engine.respond(prompt: prompt, history: history, conversationID: convoID, settings: chatSettings) { partial in
                    self.update(placeholder.id, in: convoID, text: partial)
                }
            } catch {
                failure = error
            }
            self.finish(placeholder.id, in: convoID, failure: failure)
        }
    }

    private func update(_ id: UUID, in convoID: UUID, text: String) {
        guard let ci = store.index(of: convoID), let mi = store.conversations[ci].messages.firstIndex(where: { $0.id == id }) else { return }
        store.conversations[ci].messages[mi].text = text
    }

    private func finish(_ id: UUID, in convoID: UUID, failure: Error?) {
        defer { isGenerating = false; streamingID = nil; store.save() }
        guard let ci = store.index(of: convoID), let mi = store.conversations[ci].messages.firstIndex(where: { $0.id == id }) else { return }
        store.conversations[ci].updatedAt = Date()
        let cancelled = failure is CancellationError || Task.isCancelled
        if let failure, !cancelled {
            store.conversations[ci].messages[mi].text = ChatEngine.describe(failure)
            store.conversations[ci].messages[mi].isError = true
            engine.invalidate()
            if settings.haptics { notify.notificationOccurred(.error) }
        } else if store.conversations[ci].messages[mi].text.isEmpty {
            store.conversations[ci].messages.remove(at: mi)          // stopped before any text arrived
        } else if settings.haptics {
            notify.notificationOccurred(.success)
        }
        if !cancelled, failure == nil, store.conversations[ci].messages.indices.contains(mi) {
            AccessibilityNotification.Announcement("Reply finished").post()
        }
    }

    func stop() {
        task?.cancel()
    }
}
