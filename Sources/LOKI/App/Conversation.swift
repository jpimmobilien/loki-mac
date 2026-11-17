import Foundation
import LokiCore

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
        /// Hinweis im Chat: Modellwechsel, Warnung, Fehler
        case notice
    }

    enum NoticeKind: String, Codable {
        case modelSwitch
        case info
        case warning
        case error
    }

    var id = UUID()
    var role: Role
    var text: String
    var reasoning: String?
    var modelID: String?
    var modelName: String?
    var routeReason: String?
    var noticeKind: NoticeKind?
    /// Vorschlag für einen Wechsel (manueller Modus mit erlaubter Option)
    var suggestedModelID: String?
    var stats: GenerationStats?
    var date = Date()
    var isStreaming = false
    var wasCancelled = false
}

struct Conversation: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var created = Date()
    var updated = Date()
    var mode: RouterMode
    var manualModelID: String?
    var messages: [ChatMessage] = []
    var isDemo = false

    /// Modell, das zuletzt geantwortet hat
    var lastModelID: String? { messages.last(where: { $0.role == .assistant && $0.modelID != nil })?.modelID }

    /// Verlauf für die Context Engine (ohne Hinweise, ohne Denkblöcke)
    var contextTurns: [ContextTurn] {
        messages.compactMap { message in
            switch message.role {
            case .user: return ContextTurn(role: .user, text: message.text)
            case .assistant:
                guard !message.text.isEmpty else { return nil }
                return ContextTurn(role: .assistant, text: message.text, modelName: message.modelName)
            case .notice: return nil
            }
        }
    }

    static func titled(from text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if flat.count <= 48 { return flat }
        let cut = flat.prefix(48)
        if let space = cut.lastIndex(of: " ") { return String(cut[..<space]) + " …" }
        return String(cut) + " …"
    }
}

/// Trennt den Denkblock (<think>…</think>) von der eigentlichen Antwort.
enum ThinkingParser {
    static func split(_ raw: String) -> (reasoning: String?, answer: String) {
        var text = raw
        // gpt-oss: Kanäle „analysis“ und „final“
        if let finalRange = text.range(of: "<|channel|>final<|message|>") {
            let reasoning = String(text[..<finalRange.lowerBound])
                .replacingOccurrences(of: "<|channel|>analysis<|message|>", with: "")
                .replacingOccurrences(of: "<|end|>", with: "")
                .replacingOccurrences(of: "<|start|>assistant", with: "")
            let answer = String(text[finalRange.upperBound...]).replacingOccurrences(of: "<|return|>", with: "")
            return (reasoning.trimmingCharacters(in: .whitespacesAndNewlines), answer.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if text.hasPrefix("<|channel|>analysis<|message|>") {
            return (String(text.dropFirst("<|channel|>analysis<|message|>".count)), "")
        }
        guard let open = text.range(of: "<think>") else {
            // Manche Vorlagen setzen <think> schon in den Prompt – dann steht nur </think> in der Ausgabe
            if let close = text.range(of: "</think>") {
                let reasoning = String(text[..<close.lowerBound])
                let answer = String(text[close.upperBound...])
                return (reasoning.trimmingCharacters(in: .whitespacesAndNewlines), answer.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return (nil, text)
        }
        let before = String(text[..<open.lowerBound])
        text = String(text[open.upperBound...])
        if let close = text.range(of: "</think>") {
            let reasoning = String(text[..<close.lowerBound])
            let answer = before + String(text[close.upperBound...])
            return (reasoning.trimmingCharacters(in: .whitespacesAndNewlines), answer.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Denkblock läuft noch
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), before)
    }
}
