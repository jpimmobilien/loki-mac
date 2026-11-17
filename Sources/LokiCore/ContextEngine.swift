import Foundation

/// Ein Gesprächsschritt, unabhängig vom Modell gespeichert.
public struct ContextTurn: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }
    public var role: Role
    public var text: String
    public var modelName: String?

    public init(role: Role, text: String, modelName: String? = nil) {
        self.role = role
        self.text = text
        self.modelName = modelName
    }
}

/// Kontextpaket für ein Zielmodell
public struct ContextPack: Sendable, Equatable {
    /// Systemanweisung inklusive Zusammenfassung älterer Teile
    public var instructions: String
    /// wörtlich übernommene Gesprächsschritte (älteste zuerst)
    public var turns: [ContextTurn]
    /// Anzahl zusammengefasster älterer Schritte
    public var summarizedCount: Int
    public var estimatedTokens: Int
}

/// Die Context Engine hält den Verlauf modellunabhängig und baut bei jedem Wechsel ein Kontextpaket
/// für das Zielmodell: Rolle und Regeln, die letzten Schritte wörtlich, ältere Teile als Zusammenfassung.
/// Das Paket nutzt höchstens rund 60 % des Kontextfensters; der Rest bleibt für die Antwort.
public enum ContextEngine {
    public static let baseInstructions = """
    Du bist LOKI, ein KI-Assistent, der vollständig lokal auf dem Mac des Nutzers läuft. \
    Antworte auf Deutsch, außer der Nutzer schreibt in einer anderen Sprache. \
    Antworte klar und genau. Wenn du etwas nicht weißt, sag es offen.
    """

    public static func budget(forContextWindow window: Int, cap: Int = 32_768) -> Int {
        min(Int(Double(window) * 0.6), cap)
    }

    public static func build(
        history: [ContextTurn], budgetTokens: Int, instructions: String = baseInstructions
    ) -> ContextPack {
        let instructionTokens = TaskClassifier.estimateTokens(instructions)
        let verbatimBudget = Int(Double(budgetTokens) * 0.75) - instructionTokens
        var kept: [ContextTurn] = []
        var used = 0
        var index = history.count - 1
        while index >= 0 {
            let cost = TaskClassifier.estimateTokens(history[index].text) + 8
            if used + cost > verbatimBudget, !kept.isEmpty { break }
            if used + cost > verbatimBudget {
                // Eine einzelne sehr lange Nachricht: gekürzt übernehmen statt verwerfen
                let allowedChars = max(200, Int(Double(verbatimBudget) * 3.5))
                var turn = history[index]
                turn.text = String(turn.text.suffix(allowedChars))
                kept.insert(turn, at: 0)
                used += TaskClassifier.estimateTokens(turn.text)
                index -= 1
                break
            }
            kept.insert(history[index], at: 0)
            used += cost
            index -= 1
        }
        // Gesprächsschritte müssen mit einer Nutzernachricht beginnen
        while let first = kept.first, first.role == .assistant {
            kept.removeFirst()
            index += 1
        }

        let older = Array(history.prefix(max(0, index + 1)))
        var text = instructions
        if !older.isEmpty {
            let summaryBudgetChars = Int(Double(budgetTokens) * 0.2 * 3.5)
            text += "\n\nZusammenfassung des bisherigen Gesprächs (ältere Teile, gekürzt):\n"
            text += summarize(older, maxChars: summaryBudgetChars)
        }
        let total = TaskClassifier.estimateTokens(text) + kept.reduce(0) { $0 + TaskClassifier.estimateTokens($1.text) + 8 }
        return ContextPack(instructions: text, turns: kept, summarizedCount: older.count, estimatedTokens: total)
    }

    /// Einfache, nachvollziehbare Zusammenfassung: der Anfang jedes älteren Schritts.
    static func summarize(_ turns: [ContextTurn], maxChars: Int) -> String {
        guard !turns.isEmpty else { return "" }
        let perTurn = max(60, maxChars / max(1, turns.count))
        var lines: [String] = []
        for turn in turns {
            let flat = turn.text.replacingOccurrences(of: "\n", with: " ")
            let short = flat.count > perTurn ? String(flat.prefix(perTurn)) + " …" : flat
            let who = turn.role == .user ? "Nutzer" : "Antwort\(turn.modelName.map { " (\($0))" } ?? "")"
            lines.append("- \(who): \(short)")
        }
        var result = lines.joined(separator: "\n")
        if result.count > maxChars { result = String(result.suffix(maxChars)) }
        return result
    }
}
