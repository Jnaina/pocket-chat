import Foundation
import FoundationModels

/// Wraps Apple's on-device language model (Apple Intelligence) from the Foundation Models framework.
/// Nothing is sent off the phone: `SystemLanguageModel.default` runs locally.
@MainActor
final class ChatEngine: ObservableObject {
    enum Status: Equatable {
        case ready
        case unavailable(title: String, detail: String)
        var isReady: Bool { self == .ready }
    }

    @Published private(set) var status: Status = .ready
    private var session: LanguageModelSession?
    private var sessionKey = ""

    init() { refreshAvailability() }

    func refreshAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available:
            status = .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                status = .unavailable(title: "Apple Intelligence isn't supported here",
                                      detail: "This device can't run the on-device model. Apple Intelligence needs an iPhone 15 Pro or newer.")
            case .appleIntelligenceNotEnabled:
                status = .unavailable(title: "Turn on Apple Intelligence",
                                      detail: "Open Settings > Apple Intelligence & Siri and switch Apple Intelligence on, then come back.")
            case .modelNotReady:
                status = .unavailable(title: "The model isn't ready yet",
                                      detail: "Apple Intelligence is still downloading or preparing its model. Try again in a few minutes.")
            @unknown default:
                status = .unavailable(title: "The model is unavailable", detail: "Apple Intelligence can't be used right now.")
            }
        @unknown default:
            status = .unavailable(title: "The model is unavailable", detail: "Apple Intelligence can't be used right now.")
        }
    }

    /// Forget the current session (after regenerate, delete, or a settings change).
    func invalidate() { session = nil; sessionKey = "" }

    private func session(for id: UUID, history: [ChatMessage], settings: ChatSettings, recapChars: Int) -> LanguageModelSession {
        let key = "\(id.uuidString)|\(settings.signature)"
        if let s = session, key == sessionKey { return s }
        let text = ChatLogic.sessionInstructions(settings: settings, history: history, recapChars: recapChars)
        let s = LanguageModelSession(instructions: text)
        session = s
        sessionKey = key
        return s
    }

    /// Gets the model ready ahead of the first prompt so the first reply starts sooner.
    func prewarm(conversationID: UUID, history: [ChatMessage], settings: ChatSettings) {
        guard status.isReady else { return }
        session(for: conversationID, history: history, settings: settings, recapChars: 5000).prewarm()
    }

    /// Streams a reply. `history` is everything said BEFORE `prompt`. Returns the final text.
    /// If the conversation outgrows the model's small context window it is condensed and retried once.
    func respond(prompt: String, history: [ChatMessage], conversationID: UUID, settings: ChatSettings,
                 onPartial: (String) -> Void) async throws -> String {
        var attempt = 0
        while true {
            let s = session(for: conversationID, history: history, settings: settings, recapChars: attempt == 0 ? 5000 : 2000)
            do {
                var latest = ""
                let options = GenerationOptions(temperature: settings.temperature, maximumResponseTokens: settings.maxTokens)
                for try await snapshot in s.streamResponse(to: prompt, options: options) {
                    latest = snapshot.content
                    onPartial(latest)
                }
                return latest
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error, attempt == 0 {
                    attempt += 1
                    invalidate()
                    continue
                }
                throw error
            }
        }
    }

    /// A short, friendly explanation of what went wrong.
    static func describe(_ error: Error) -> String {
        guard let e = error as? LanguageModelSession.GenerationError else { return error.localizedDescription }
        switch e {
        case .exceededContextWindowSize: return "This conversation is too long for the on-device model. Start a new chat."
        case .assetsUnavailable: return "The on-device model isn't downloaded yet. Check Settings > Apple Intelligence & Siri."
        case .guardrailViolation: return "The model can't help with that request."
        case .refusal: return "The model declined to answer that."
        case .unsupportedLanguageOrLocale: return "That language isn't supported by the on-device model yet."
        case .rateLimited: return "The model is busy. Try again in a moment."
        case .concurrentRequests: return "The model is already working on a reply."
        default: return e.localizedDescription
        }
    }
}
