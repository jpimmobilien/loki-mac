import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXVLM
import LokiCore

struct LoadedModelInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var bytes: Int64
    var loadSeconds: Double
    var loadedAt: Date
}

enum RuntimeActivity: Equatable {
    case idle
    case loading(name: String, estimatedSeconds: Double?, started: Date)
    case generating(name: String, tokens: Int, tokensPerSecond: Double)
}

struct GenerationStats: Codable, Equatable {
    var promptTokens: Int
    var tokens: Int
    var tokensPerSecond: Double
    var timeToFirstToken: Double
    var promptTokensPerSecond: Double
}

enum RuntimeError: LocalizedError {
    case notLoaded(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded(let name): return "\(name) ist nicht geladen."
        }
    }
}

/// Lokale Inferenz mit MLX: Modelle laden, entladen und Antworten streamen.
/// Ein Chat behält seine Sitzung (und damit den KV-Cache), solange das Modell gleich bleibt.
@MainActor
final class ModelRuntime: ObservableObject {
    @Published private(set) var loaded: [String: LoadedModelInfo] = [:]
    @Published private(set) var activity: RuntimeActivity = .idle

    private var containers: [String: ModelContainer] = [:]
    private var sessions: [UUID: CachedSession] = [:]

    private struct CachedSession {
        var modelID: String
        var session: ChatSession
        /// Anzahl der Gesprächsschritte, die die Sitzung bereits kennt
        var turnCount: Int
        var thinking: Bool?
    }

    init() {
        // Puffer-Cache von MLX begrenzen, damit entladene Modelle den Speicher wirklich freigeben
        MLX.Memory.cacheLimit = 2 * 1024 * 1024 * 1024
    }

    func isLoaded(_ id: String) -> Bool { containers[id] != nil }

    var loadedBytes: Int64 { loaded.values.reduce(0) { $0 + $1.bytes } }

    /// Lädt ein Modell. Vorher werden andere Modelle entladen, wenn das Limit oder der Speicher es verlangt –
    /// nie laufen unnötig mehrere große Modelle parallel.
    func ensureLoaded(_ model: InstalledModel, maxLoaded: Int, budget: Int64, readSpeed: Double?) async throws {
        if containers[model.id] != nil { return }
        let byAge = loaded.values.sorted { $0.loadedAt < $1.loadedAt }
        for info in byAge {
            let tooMany = containers.count >= max(1, maxLoaded)
            let tooBig = !Router.fits(bytes: model.bytes + loadedBytes, budget: budget)
            if tooMany || tooBig { unload(info.id) }
        }
        activity = .loading(
            name: model.descriptor.name,
            estimatedSeconds: readSpeed.map { Double(model.bytes) / max($0, 1) },
            started: Date())
        defer { activity = .idle }
        let start = Date()
        let container = try await loadModelContainer(from: model.directory, using: LocalTokenizerLoader())
        containers[model.id] = container
        loaded[model.id] = LoadedModelInfo(
            id: model.id, name: model.descriptor.name, bytes: model.bytes,
            loadSeconds: Date().timeIntervalSince(start), loadedAt: Date())
    }

    func unload(_ id: String) {
        containers[id] = nil
        loaded[id] = nil
        sessions = sessions.filter { $0.value.modelID != id }
        MLX.Memory.clearCache()
    }

    func unloadAll() {
        for id in Array(containers.keys) { unload(id) }
    }

    func forgetSession(_ conversationID: UUID) { sessions[conversationID] = nil }

    /// Nur für Vorschaubilder im Prüfmodus: Anzeige „geladen“ ohne echtes Modell
    func injectDemoLoaded(_ info: LoadedModelInfo) { loaded[info.id] = info }

    /// Erzeugt eine Antwort. `pack` enthält den Verlauf für dieses Modell (von der Context Engine gebaut);
    /// er wird nur genutzt, wenn keine passende Sitzung besteht (z. B. nach einem Modellwechsel).
    func generate(
        conversationID: UUID, modelID: String, modelName: String, pack: ContextPack, priorTurnCount: Int,
        prompt: String, thinking: Bool?, maxTokens: Int, temperature: Float,
        onText: @escaping (String) -> Void
    ) async throws -> GenerationStats {
        guard let container = containers[modelID] else { throw RuntimeError.notLoaded(modelName) }

        var cached = sessions[conversationID]
        if let c = cached, c.modelID != modelID || c.turnCount != priorTurnCount || c.thinking != thinking {
            cached = nil
        }
        let session: ChatSession
        if let c = cached {
            session = c.session
        } else {
            var history: [Chat.Message] = [.system(pack.instructions)]
            for turn in pack.turns {
                history.append(turn.role == .user ? .user(turn.text) : .assistant(turn.text))
            }
            session = ChatSession(
                container,
                history: history,
                generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: temperature, topP: 0.95),
                additionalContext: thinking.map { flag -> [String: any Sendable] in ["enable_thinking": flag] })
        }

        let start = Date()
        var firstTokenAt: Date?
        var stats = GenerationStats(promptTokens: 0, tokens: 0, tokensPerSecond: 0, timeToFirstToken: 0, promptTokensPerSecond: 0)
        var produced = 0
        activity = .generating(name: modelName, tokens: 0, tokensPerSecond: 0)
        defer { activity = .idle }

        do {
            for try await event in session.streamDetails(to: prompt) {
                try Task.checkCancellation()
                switch event {
                case .chunk(let text):
                    if firstTokenAt == nil { firstTokenAt = Date() }
                    produced += 1
                    onText(text)
                    if produced % 8 == 0, let first = firstTokenAt {
                        let elapsed = Date().timeIntervalSince(first)
                        activity = .generating(name: modelName, tokens: produced, tokensPerSecond: elapsed > 0 ? Double(produced) / elapsed : 0)
                    }
                case .info(let info):
                    stats = GenerationStats(
                        promptTokens: info.promptTokenCount, tokens: info.generationTokenCount,
                        tokensPerSecond: info.tokensPerSecond, timeToFirstToken: 0,
                        promptTokensPerSecond: info.promptTokensPerSecond)
                default:
                    break
                }
            }
        } catch {
            // Nach einem Abbruch ist der Zustand der Sitzung unklar → beim nächsten Mal neu aufbauen
            sessions[conversationID] = nil
            throw error
        }
        stats.timeToFirstToken = (firstTokenAt ?? Date()).timeIntervalSince(start)
        sessions[conversationID] = CachedSession(modelID: modelID, session: session, turnCount: priorTurnCount + 2, thinking: thinking)
        return stats
    }
}
