import Foundation
import LokiCore

/// Demo-Daten nur für Vorschaubilder im Prüfmodus. Sie werden nie gespeichert und sind in der Oberfläche markiert.
@MainActor
enum QADemo {
    static let chatAutoID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let chatManualID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    static func populate(_ model: AppModel) {
        model.isQAMode = true
        let root = AppPaths.dataDirectory.appendingPathComponent("Demo-Modellordner", isDirectory: true)
        model.chooseModelRoot(root)

        let ids = ["mlx-community/Qwen3-4B-4bit", "mlx-community/gemma-4-26b-a4b-it-4bit", "mlx-community/Qwen3.6-27B-4bit"]
        let demoModels = ids.compactMap { id -> InstalledModel? in
            guard let d = Catalog.descriptor(for: id) else { return nil }
            return InstalledModel(
                id: id, descriptor: d, directory: root.appendingPathComponent("Modelle/\(d.folderName)"),
                bytes: d.approxBytes, modelType: "demo", isSupported: true, isAvailable: true, isDemo: true)
        }
        model.library.injectDemo(demoModels)
        if let gemma = demoModels.first(where: { $0.id.contains("gemma") }) {
            model.runtime.injectDemoLoaded(LoadedModelInfo(id: gemma.id, name: gemma.descriptor.name, bytes: gemma.bytes, loadSeconds: 34, loadedAt: Date()))
        }
        model.settings.measuredSpeed = [
            "mlx-community/Qwen3-4B-4bit": 96,
            "mlx-community/gemma-4-26b-a4b-it-4bit": 58,
            "mlx-community/Qwen3.6-27B-4bit": 17,
        ]

        let gemma = "mlx-community/gemma-4-26b-a4b-it-4bit"
        let qwen = "mlx-community/Qwen3.6-27B-4bit"
        var auto = Conversation(title: "Exposé Altbauwohnung Südstadt", mode: .auto)
        auto.id = chatAutoID
        auto.isDemo = true
        auto.messages = [
            ChatMessage(role: .user, text: "Schreibe ein kurzes Exposé für eine 3-Zimmer-Altbauwohnung, 92 m², Stuck, Balkon, renoviertes Bad."),
            ChatMessage(
                role: .assistant,
                text: "**Charmanter Altbau mit Stuck und Balkon**\n\nDiese helle 3-Zimmer-Wohnung verbindet den Charme der Jahrhundertwende mit modernem Komfort. Auf rund 92 m² erwarten Sie hohe Decken mit original Stuck, ein frisch renoviertes Bad und ein ruhiger Balkon für den Morgenkaffee.\n\n• 3 Zimmer, Küche, Bad\n• Stuckdecken und Dielenboden\n• Balkon zum Innenhof",
                modelID: gemma, modelName: "Gemma 4 26B A4B",
                routeReason: "Gemma 4 26B A4B – Text schreiben, schon geladen, beste Qualität für diese Aufgabe",
                stats: GenerationStats(promptTokens: 212, tokens: 168, tokensPerSecond: 58, timeToFirstToken: 0.4, promptTokensPerSecond: 900)),
            ChatMessage(role: .user, text: "Vergleiche bitte Kaufpreis und Miete: Lohnt sich bei 4.200 €/m² und 14 €/m² Kaltmiete eher Kauf oder Miete? Begründe Schritt für Schritt."),
            notice(.modelSwitch, "Wechsel von Gemma 4 26B A4B zu Qwen3.6 27B · Analysieren: Qwen3.6 27B ist hier 21 % besser bewertet"),
            ChatMessage(
                role: .assistant,
                text: "Kurz gerechnet: Der Kaufpreis liegt bei rund 386.400 € (92 m² × 4.200 €). Die Jahreskaltmiete beträgt 15.456 € (92 m² × 14 € × 12). Das ergibt einen Kaufpreisfaktor von etwa **25** – das entspricht einer Bruttorendite von rund 4 %.\n\nBei einem Faktor über 25 ist Mieten finanziell meist günstiger, solange die Zinsen nicht deutlich fallen. Entscheidend sind außerdem Nebenkosten beim Kauf (Grunderwerbsteuer, Notar, Makler) und wie lange du bleiben willst.",
                reasoning: "Kaufpreis 92 × 4200 = 386.400. Jahresmiete 92 × 14 × 12 = 15.456. Faktor = 25,0 …",
                modelID: qwen, modelName: "Qwen3.6 27B",
                routeReason: "Analysieren: Qwen3.6 27B ist hier 21 % besser bewertet",
                stats: GenerationStats(promptTokens: 640, tokens: 214, tokensPerSecond: 17, timeToFirstToken: 1.6, promptTokensPerSecond: 410)),
        ]

        var manual = Conversation(title: "Swift: Liste nach Jahr sortieren", mode: .manual, manualModelID: "mlx-community/Qwen3-4B-4bit")
        manual.id = chatManualID
        manual.isDemo = true
        manual.messages = [
            ChatMessage(role: .user, text: "Wie sortiere ich in Swift eine Liste von Alben nach Erscheinungsjahr?"),
            ChatMessage(
                role: .assistant,
                text: "Mit `sorted(by:)` und dem Jahr als Schlüssel:\n\n```swift\nlet sortiert = alben.sorted { $0.jahr < $1.jahr }\n```\n\nFür absteigende Reihenfolge tauschst du einfach `<` gegen `>`.",
                modelID: "mlx-community/Qwen3-4B-4bit", modelName: "Qwen3 4B", routeReason: "Manuell gewählt",
                stats: GenerationStats(promptTokens: 120, tokens: 64, tokensPerSecond: 96, timeToFirstToken: 0.2, promptTokensPerSecond: 1400)),
            notice(.warning, "Hinweis: Qwen3 4B kann keine Bilder lesen."),
        ]
        var third = Conversation(title: "Nebenkostenabrechnung erklären", mode: .auto)
        third.isDemo = true
        third.updated = Date().addingTimeInterval(-86_400 * 3)
        third.messages = [ChatMessage(role: .user, text: "Was gehört in eine Nebenkostenabrechnung?")]
        model.conversations = [auto, manual, third] + model.conversations.filter { !$0.isDemo }
    }

    private static func notice(_ kind: ChatMessage.NoticeKind, _ text: String) -> ChatMessage {
        var message = ChatMessage(role: .notice, text: text)
        message.noticeKind = kind
        return message
    }
}
