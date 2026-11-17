import Foundation

/// Ergebnis der Aufgabenerkennung: Aufgabenart, zwingend nötige Fähigkeiten, geschätzte Kontextgröße.
public struct TaskProfile: Sendable, Equatable {
    public var kind: TaskKind
    public var required: Set<Capability>
    public var estimatedTokens: Int
    /// 1 (leicht) … 5 (schwer)
    public var difficulty: Int
    /// Denkmodus einschalten (nur bei Modellen, die ihn kennen)
    public var wantsThinking: Bool

    public init(kind: TaskKind, required: Set<Capability> = [], estimatedTokens: Int, difficulty: Int, wantsThinking: Bool = false) {
        self.kind = kind
        self.required = required
        self.estimatedTokens = estimatedTokens
        self.difficulty = difficulty
        self.wantsThinking = wantsThinking
    }
}

/// Regelbasierte Aufgabenerkennung. Später kommt das Apple-Systemmodell mit strukturierter Ausgabe dazu;
/// die Regeln bleiben als schneller, nachvollziehbarer Vorfilter.
public enum TaskClassifier {
    /// Grobe Schätzung: im Deutschen rund 3,5 Zeichen je Token.
    public static func estimateTokens(_ text: String) -> Int {
        Int((Double(text.count) / 3.5).rounded(.up))
    }

    static let codeHints = [
        "```", "func ", "class ", "struct ", "def ", "import ", "#include", "var ", "let ", "=>", "</",
        "swift", "swiftui", "kotlin", "python", "javascript", "typescript", "java ", "c++", "sql", "regex",
        "xcode", "gradle", "android studio", "compiler", "kompilier", "build-fehler", "stacktrace", "exception",
        "programmier", "quellcode", "code", "funktion schreiben", "bugfix", "refactor", "unit-test",
    ]
    static let reasoningHints = [
        "warum", "weshalb", "begründe", "analysier", "analyse", "vergleiche", "vergleich", "berechne",
        "rechne", "beweis", "schritt für schritt", "strategie", "vor- und nachteile", "vorteile und nachteile",
        "abwägen", "bewerte", "plane", "entscheidung", "logik", "rätsel", "wahrscheinlich", "prognose",
    ]
    static let writingHints = [
        "schreib", "formulier", "e-mail", "email", "brief", "anschreiben", "text für", "artikel", "blog",
        "zusammenfass", "übersetz", "exposé", "expose", "beschreibung", "anzeige", "korrigier", "umschreiben",
        "kürze", "gliederung", "protokoll",
    ]

    public static func classify(_ text: String, historyText: String = "", hasImage: Bool = false) -> TaskProfile {
        let lower = text.lowercased()
        let estimated = estimateTokens(historyText) + estimateTokens(text) + 1024

        func contains(_ hints: [String]) -> Int { hints.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) } }
        let code = contains(codeHints)
        let reasoning = contains(reasoningHints)
        let writing = contains(writingHints)
        let long = text.count > 6000

        var kind: TaskKind
        var required: Set<Capability> = []
        if hasImage {
            kind = .vision
            required.insert(.vision)
        } else if estimated > 24_000 {
            kind = .longContext
            required.insert(.longContext)
        } else if code >= 2 || text.contains("```") {
            kind = .coding
        } else if reasoning >= 1 && reasoning >= writing {
            kind = .reasoning
        } else if writing >= 1 {
            kind = .writing
        } else if code == 1 {
            kind = .coding
        } else if text.count < 140 && !long {
            kind = .quick
        } else {
            kind = .chat
        }

        var difficulty = 2
        if kind == .quick { difficulty = 1 }
        if kind == .coding || kind == .reasoning { difficulty = 3 }
        if text.count > 1500 { difficulty += 1 }
        if reasoning >= 3 || code >= 4 { difficulty += 1 }
        difficulty = min(5, max(1, difficulty))

        return TaskProfile(
            kind: kind, required: required, estimatedTokens: estimated, difficulty: difficulty,
            wantsThinking: kind == .reasoning || (kind == .coding && difficulty >= 4))
    }
}
