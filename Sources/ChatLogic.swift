import Foundation

// Pure logic (no UI, no model framework) so it can be unit-tested from the command line.

enum Role: String, Codable { case user, assistant }

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var isError = false
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "New chat"
    var messages: [ChatMessage] = []
    var updatedAt = Date()
}

enum Persona: Int, CaseIterable, Identifiable {
    case assistant, concise, tutor, writer, custom
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .assistant: return "Helpful assistant"
        case .concise: return "Concise"
        case .tutor: return "Patient tutor"
        case .writer: return "Creative writer"
        case .custom: return "Custom"
        }
    }

    var instructions: String {
        switch self {
        case .assistant: return "You are a helpful, friendly assistant running privately on the user's iPhone. Answer clearly and accurately."
        case .concise: return "You are a concise assistant. Answer in one to three short sentences unless the user asks for more detail."
        case .tutor: return "You are a patient tutor. Explain step by step with simple examples, and check that the user understands."
        case .writer: return "You are an imaginative writing partner. Use vivid, original language and offer fresh ideas."
        case .custom: return ""
        }
    }
}

enum ResponseLength: Int, CaseIterable, Identifiable {
    case short, normal, long
    var id: Int { rawValue }
    var name: String { ["Short", "Normal", "Long"][rawValue] }
    var maxTokens: Int { [220, 700, 1400][rawValue] }
}

struct ChatSettings: Equatable {
    var persona = Persona.assistant
    var custom = ""
    var creativity = 0.45          // 0...1
    var length = ResponseLength.normal

    /// The system instructions given to the model.
    var instructions: String {
        var base = persona == .custom && !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? custom.trimmingCharacters(in: .whitespacesAndNewlines)
            : (persona == .custom ? Persona.assistant.instructions : persona.instructions)
        base += " If you are not sure about something, say so instead of guessing."
        return base
    }

    var temperature: Double { max(0, min(1, creativity)) * 1.5 }
    var maxTokens: Int { length.maxTokens }

    /// Changes whenever the model would need a fresh session.
    var signature: String { "\(instructions)|\(length.rawValue)" }
}

enum ChatLogic {
    /// A short title taken from the first user message.
    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "New chat" }
        return t.count > 40 ? String(t.prefix(40)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    /// Condensed earlier conversation, newest messages kept first when space runs out.
    /// The on-device model has a small context window, so this is deliberately compact.
    static func recap(of messages: [ChatMessage], maxChars: Int, perMessage: Int = 500) -> String {
        var lines: [String] = []
        var used = 0
        for m in messages.reversed() where !m.isError && !m.text.isEmpty {
            var t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > perMessage { t = String(t.prefix(perMessage)) + "…" }
            let line = (m.role == .user ? "User: " : "Assistant: ") + t
            if used + line.count > maxChars && !lines.isEmpty { break }
            lines.append(line)
            used += line.count
        }
        return lines.reversed().joined(separator: "\n")
    }

    /// Full instructions for a (re)built session, including a recap of what was said before.
    static func sessionInstructions(settings: ChatSettings, history: [ChatMessage], recapChars: Int) -> String {
        let r = recap(of: history, maxChars: recapChars)
        return r.isEmpty ? settings.instructions : settings.instructions + "\n\nThe conversation so far:\n" + r
    }
}
