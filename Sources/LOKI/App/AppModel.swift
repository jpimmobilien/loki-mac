import Foundation
import SwiftUI
import AppKit
import LokiCore

enum AppTab: String, CaseIterable, Identifiable {
    case home, chat, coding, documents, presentations, tables, studio, models, projects, history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "Chat"
        case .coding: return "Coding"
        case .documents: return "Dokumente"
        case .presentations: return "Präsentationen"
        case .tables: return "Tabellen"
        case .studio: return "Studio"
        case .models: return "Modelle"
        case .projects: return "Projekte"
        case .history: return "Verlauf"
        case .settings: return "Einstellungen"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .chat: return "bubble.left.and.bubble.right"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .documents: return "doc.text"
        case .presentations: return "rectangle.on.rectangle.angled"
        case .tables: return "tablecells"
        case .studio: return "paintpalette"
        case .models: return "cpu"
        case .projects: return "folder"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    /// In LOKI 0.1 nutzbar; die übrigen Bereiche zeigen, was geplant ist
    var isAvailable: Bool { [.home, .chat, .models, .history, .settings].contains(self) }

    static let primary: [AppTab] = [.home, .chat, .coding, .documents, .presentations, .tables]
    static let secondary: [AppTab] = [.studio, .models, .projects, .history]
}

/// Zentrale Steuerung der App: Chats, AUTO-Router, Context Engine, Laden und Antworten.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var tab: AppTab = .home
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationID: UUID?
    @Published var draft = ""
    /// Modus und Modellwahl für einen neuen Chat (vom Home-Eingabefeld)
    @Published var draftMode: RouterMode
    @Published var draftManualModelID: String?
    @Published private(set) var isGenerating = false
    @Published var toast: String?
    @Published var isQAMode = false

    let settings: SettingsStore
    let hardware = HardwareMonitor()
    let storage = StorageManager()
    let network = NetworkMonitor()
    let library = ModelLibrary()
    let runtime = ModelRuntime()

    private var generationTask: Task<Void, Never>?

    init() {
        let qa = ProcessInfo.processInfo.environment["LOKI_DATA_DIR"] != nil
        settings = SettingsStore(defaults: qa ? (UserDefaults(suiteName: "de.jpimmobilien.loki.qa") ?? .standard) : .standard)
        draftMode = settings.defaultMode
        library.setRoot(settings.modelRoot)
        storage.onVolumesChanged = { [weak self] in
            self?.library.rescan()
        }
        loadConversations()
    }

    // MARK: - Chats

    var selectedConversation: Conversation? { conversations.first { $0.id == selectedConversationID } }

    private func index(of id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }

    func newConversation() {
        selectedConversationID = nil
        draftMode = settings.defaultMode
        tab = .chat
    }

    func select(_ id: UUID) {
        selectedConversationID = id
        tab = .chat
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        runtime.forgetSession(id)
        if selectedConversationID == id { selectedConversationID = nil }
        save()
    }

    /// Modus des aktuellen Chats (oder des nächsten neuen Chats)
    var currentMode: RouterMode {
        get { selectedConversation?.mode ?? draftMode }
        set {
            if let id = selectedConversationID, let i = index(of: id) {
                conversations[i].mode = newValue
                if newValue == .manual, conversations[i].manualModelID == nil {
                    conversations[i].manualModelID = conversations[i].lastModelID ?? defaultManualModel()
                }
                save()
            } else {
                draftMode = newValue
                if newValue == .manual, draftManualModelID == nil { draftManualModelID = defaultManualModel() }
            }
        }
    }

    var currentManualModelID: String? {
        get { selectedConversation.map { $0.manualModelID } ?? draftManualModelID }
        set {
            if let id = selectedConversationID, let i = index(of: id) {
                conversations[i].manualModelID = newValue
                save()
            } else {
                draftManualModelID = newValue
            }
        }
    }

    private func defaultManualModel() -> String? {
        if let loaded = runtime.loaded.keys.first { return loaded }
        return usableModels.first?.id
    }

    /// Installierte, verbundene und unterstützte Modelle
    var usableModels: [InstalledModel] { library.installed.filter { $0.isAvailable && $0.isSupported } }

    // MARK: - Modellordner und Laufwerk

    func chooseModelRoot(_ url: URL) {
        settings.modelRootPath = url.path
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("Modelle"), withIntermediateDirectories: true)
        library.setRoot(url)
        storage.refresh()
    }

    var modelRootVolume: VolumeInfo? { settings.modelRoot.flatMap { storage.volume(containing: $0) } }

    var readSpeedForRoot: Double? { modelRootVolume.flatMap { settings.driveReadSpeed[$0.id] } }

    func measureDriveSpeed() async {
        guard let root = settings.modelRoot, library.rootReachable else { return }
        if let speed = await storage.measureReadSpeed(in: root), let volume = modelRootVolume {
            settings.driveReadSpeed[volume.id] = speed
        }
    }

    func download(_ id: String, name: String? = nil) {
        library.download(id: id, name: name, availableSpace: modelRootVolume?.available)
    }

    // MARK: - Router

    func routerCandidates() -> [RouterCandidate] {
        library.installed.filter(\.isSupported).map { model in
            RouterCandidate(
                descriptor: model.descriptor, isAvailable: model.isAvailable, isLoaded: runtime.isLoaded(model.id),
                bytes: model.bytes, measuredTokensPerSecond: settings.measuredSpeed[model.id])
        }
    }

    func routerContext() -> RouterContext {
        RouterContext(
            memoryBudgetBytes: hardware.modelBudgetBytes,
            readBytesPerSecond: readSpeedForRoot ?? 450e6,
            memoryBandwidthBytesPerSecond: hardware.memoryBandwidth)
    }

    /// Vorschau der AUTO-Wahl für den aktuellen Entwurf
    func previewDecision(for text: String) -> RouteDecision? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let conv = selectedConversation
        let history = conv?.contextTurns.map(\.text).joined(separator: "\n") ?? ""
        let request = RouteRequest(
            profile: TaskClassifier.classify(trimmed, historyText: history), mode: currentMode,
            preference: settings.preference, manualModelID: currentManualModelID, currentModelID: conv?.lastModelID,
            allowSwitchInManual: settings.allowSwitchInManual)
        return Router.decide(request, candidates: routerCandidates(), context: routerContext())
    }

    // MARK: - Senden und Antworten

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        let conversationID: UUID
        if let id = selectedConversationID, index(of: id) != nil {
            conversationID = id
        } else {
            let conv = Conversation(title: Conversation.titled(from: text), mode: draftMode, manualModelID: draftManualModelID)
            conversations.insert(conv, at: 0)
            selectedConversationID = conv.id
            conversationID = conv.id
        }
        draft = ""
        tab = .chat
        append(ChatMessage(role: .user, text: text), to: conversationID)
        generationTask = Task { [weak self] in
            await self?.respond(to: text, in: conversationID)
        }
    }

    func stop() {
        generationTask?.cancel()
    }

    private func respond(to text: String, in conversationID: UUID) async {
        guard let i = index(of: conversationID) else { return }
        let conv = conversations[i]
        let turns = conv.contextTurns
        let history = Array(turns.dropLast())
        let profile = TaskClassifier.classify(text, historyText: history.map(\.text).joined(separator: "\n"))
        let request = RouteRequest(
            profile: profile, mode: conv.mode, preference: settings.preference, manualModelID: conv.manualModelID,
            currentModelID: conv.lastModelID, allowSwitchInManual: settings.allowSwitchInManual)
        let decision = Router.decide(request, candidates: routerCandidates(), context: routerContext())

        guard let modelID = decision.modelID, let model = library.installedModel(modelID) else {
            appendNotice(.error, decision.reason, to: conversationID)
            return
        }
        if let warning = decision.warning {
            appendNotice(.warning, warning, suggested: decision.suggestedModelID, to: conversationID)
        }
        if decision.isSwitch, let previous = decision.previousModelID, previous != model.id {
            let previousName = library.installedModel(previous)?.descriptor.name ?? previous
            let reason = conv.mode == .manual ? "manuell gewechselt" : decision.reason
            appendNotice(.modelSwitch, "Wechsel von \(previousName) zu \(model.descriptor.name) · \(reason)", to: conversationID)
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            try await runtime.ensureLoaded(
                model, maxLoaded: settings.maxLoadedModels, budget: hardware.modelBudgetBytes, readSpeed: readSpeedForRoot)
        } catch {
            appendNotice(.error, "\(model.descriptor.name) konnte nicht geladen werden: \(error.localizedDescription)", to: conversationID)
            return
        }
        hardware.refresh()

        let budget = ContextEngine.budget(forContextWindow: model.descriptor.contextTokens)
        let pack = ContextEngine.build(history: history, budgetTokens: budget)
        if decision.isSwitch, pack.summarizedCount > 0 {
            appendNotice(.info, "Übergabe an \(model.descriptor.name): letzte \(pack.turns.count) Schritte wörtlich, \(pack.summarizedCount) ältere zusammengefasst.", to: conversationID)
        }

        var message = ChatMessage(
            role: .assistant, text: "", modelID: model.id, modelName: model.descriptor.name,
            routeReason: conv.mode == .auto ? decision.reason : "Manuell gewählt")
        message.isStreaming = true
        let messageID = message.id
        append(message, to: conversationID)

        var raw = ""
        let thinking: Bool? = model.descriptor.supportsThinking ? profile.wantsThinking : nil
        do {
            let stats = try await runtime.generate(
                conversationID: conversationID, modelID: model.id, modelName: model.descriptor.name, pack: pack,
                priorTurnCount: history.count, prompt: text, thinking: thinking, maxTokens: 4096,
                temperature: profile.kind == .coding ? 0.3 : 0.6
            ) { [weak self] chunk in
                raw += chunk
                let parts = ThinkingParser.split(raw)
                self?.updateMessage(messageID, in: conversationID) {
                    $0.text = parts.answer
                    $0.reasoning = parts.reasoning
                }
            }
            updateMessage(messageID, in: conversationID) {
                $0.isStreaming = false
                $0.stats = stats
            }
            if stats.tokensPerSecond > 0 {
                let old = settings.measuredSpeed[model.id]
                settings.measuredSpeed[model.id] = old.map { $0 * 0.7 + stats.tokensPerSecond * 0.3 } ?? stats.tokensPerSecond
            }
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
            updateMessage(messageID, in: conversationID) {
                $0.isStreaming = false
                $0.wasCancelled = cancelled
            }
            if !cancelled {
                appendNotice(.error, "Antwort abgebrochen: \(error.localizedDescription)", to: conversationID)
            }
        }
        hardware.refresh()
        save()
    }

    func applySuggestion(_ modelID: String, in conversationID: UUID) {
        guard let i = index(of: conversationID) else { return }
        conversations[i].manualModelID = modelID
        let name = library.installedModel(modelID)?.descriptor.name ?? modelID
        appendNotice(.info, "Du hast \(name) gewählt. Die nächste Antwort kommt von diesem Modell.", to: conversationID)
    }

    // MARK: - Nachrichten

    private func append(_ message: ChatMessage, to conversationID: UUID) {
        guard let i = index(of: conversationID) else { return }
        conversations[i].messages.append(message)
        conversations[i].updated = Date()
    }

    private func appendNotice(_ kind: ChatMessage.NoticeKind, _ text: String, suggested: String? = nil, to conversationID: UUID) {
        var notice = ChatMessage(role: .notice, text: text)
        notice.noticeKind = kind
        notice.suggestedModelID = suggested
        append(notice, to: conversationID)
    }

    private func updateMessage(_ messageID: UUID, in conversationID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let i = index(of: conversationID), let j = conversations[i].messages.firstIndex(where: { $0.id == messageID }) else { return }
        change(&conversations[i].messages[j])
    }

    // MARK: - Speichern

    private func loadConversations() {
        guard let data = try? Data(contentsOf: AppPaths.conversationsFile),
              let loaded = try? JSONDecoder.loki.decode([Conversation].self, from: data) else { return }
        conversations = loaded.map { conv in
            var c = conv
            for j in c.messages.indices where c.messages[j].isStreaming {
                c.messages[j].isStreaming = false
                c.messages[j].wasCancelled = true
            }
            return c
        }
    }

    func save() {
        guard !isQAMode else { return }
        let real = conversations.filter { !$0.isDemo }
        do {
            try FileManager.default.createDirectory(at: AppPaths.dataDirectory, withIntermediateDirectories: true)
            try JSONEncoder.loki.encode(real).write(to: AppPaths.conversationsFile, options: .atomic)
        } catch {
            toast = "Chats konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
