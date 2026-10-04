import Foundation
import SwiftUI

/// Saves conversations as JSON in Application Support.
@MainActor
final class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    private let url: URL

    init() {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        url = dir.appendingPathComponent("conversations.json")
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = list
        }
    }

    func save() {
        let pruned = conversations.filter { !$0.messages.isEmpty }
        if let data = try? JSONEncoder().encode(pruned) { try? data.write(to: url, options: .atomic) }
    }

    func index(of id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }
}

/// User settings persisted in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private let d = UserDefaults.standard

    @Published var persona: Persona { didSet { d.set(persona.rawValue, forKey: "persona") } }
    @Published var custom: String { didSet { d.set(custom, forKey: "custom") } }
    @Published var creativity: Double { didSet { d.set(creativity, forKey: "creativity") } }
    @Published var length: ResponseLength { didSet { d.set(length.rawValue, forKey: "length") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }

    init() {
        persona = Persona(rawValue: d.integer(forKey: "persona")) ?? .assistant
        custom = d.string(forKey: "custom") ?? ""
        creativity = d.object(forKey: "creativity") as? Double ?? 0.45
        length = ResponseLength(rawValue: d.object(forKey: "length") as? Int ?? 1) ?? .normal
        haptics = d.object(forKey: "haptics") as? Bool ?? true
    }

    var chatSettings: ChatSettings {
        ChatSettings(persona: persona, custom: custom, creativity: creativity, length: length)
    }
}
