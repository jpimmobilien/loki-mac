import SwiftUI
import AppKit
import LokiCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var runtime: ModelRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                greeting
                if model.isQAMode { DemoBadge() }
                Composer(style: .home)
                if model.usableModels.isEmpty && !model.isQAMode {
                    FirstStepsCard()
                }
                quickActions
                HStack(alignment: .top, spacing: 16) {
                    recentChats
                    systemCard.frame(width: 330)
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "Guten Morgen"
        case 11..<17: return "Guten Tag"
        case 17..<23: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    private var greeting: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .background(
                    Circle().fill(Loki.accent.opacity(0.18)).blur(radius: 30).frame(width: 120, height: 120))
            VStack(alignment: .leading, spacing: 6) {
                Text(greetingText)
                    .font(.lokiLargeTitle)
                    .tracking(-1.2)
                Text("Was möchtest du heute erledigen? LOKI arbeitet vollständig lokal auf deinem Mac.")
                    .font(.lokiBody)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct QuickAction: Identifiable {
        var id: String { title }
        var title: String
        var subtitle: String
        var icon: String
        var tint: Color
        var planned: Bool
        var action: @MainActor (AppModel) -> Void
    }

    private var actions: [QuickAction] {
        [
            QuickAction(title: "Frage stellen", subtitle: "AUTO wählt das Modell", icon: "bubble.left.and.text.bubble.right", tint: Loki.accent, planned: false) { m in
                m.newConversation()
            },
            QuickAction(title: "Text schreiben", subtitle: "E-Mail, Exposé, Brief", icon: "pencil.line", tint: Loki.sand, planned: false) { m in
                m.newConversation()
                m.draft = "Schreibe "
            },
            QuickAction(title: "Code erklären", subtitle: "Swift, Kotlin, Python …", icon: "chevron.left.forwardslash.chevron.right", tint: Loki.steel, planned: false) { m in
                m.newConversation()
                m.draft = "Erkläre mir diesen Code:\n"
            },
            QuickAction(title: "Modelle", subtitle: "Laden, verwalten, SSD", icon: "cpu", tint: Loki.sage, planned: false) { m in
                m.tab = .models
            },
            QuickAction(title: "Dokument erstellen", subtitle: "geplant", icon: "doc.text", tint: Loki.sand, planned: true) { m in
                m.tab = .documents
            },
            QuickAction(title: "Bild erzeugen", subtitle: "geplant", icon: "photo.on.rectangle.angled", tint: Loki.steel, planned: true) { m in
                m.tab = .studio
            },
        ]
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(actions) { action in
                Button {
                    withAnimation(Loki.state) { action.action(model) }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        IconTile(systemImage: action.icon, tint: action.tint, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(action.subtitle).font(.lokiCaption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .opacity(action.planned ? 0.72 : 1)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .hoverLift()
            }
        }
    }

    private var recentChats: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Letzte Chats", detail: model.conversations.isEmpty ? nil : "\(model.conversations.count)")
            if model.conversations.isEmpty {
                Text("Noch keine Chats. Stell oben deine erste Frage – sie bleibt auf diesem Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            ForEach(model.conversations.prefix(5)) { conv in
                Button { model.select(conv.id) } label: {
                    HStack(spacing: 12) {
                        IconTile(systemImage: conv.mode == .auto ? "wand.and.stars" : "cpu", tint: conv.mode == .auto ? Loki.accent : Loki.steel, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                            Text(chatSubtitle(conv)).font(.lokiCaption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(conv.updated, style: .relative)
                            .font(.lokiCaption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Loki.surface))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.985))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .lokiCard()
    }

    private func chatSubtitle(_ conv: Conversation) -> String {
        let models = Set(conv.messages.compactMap(\.modelName)).sorted()
        let mode = conv.mode == .auto ? "Auto" : "Manuell"
        if models.isEmpty { return mode }
        return "\(mode) · \(models.joined(separator: ", "))"
    }

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Dein Mac")
            row("cpu", hardware.chipName, "\(Format.bytes(hardware.physicalMemory)) gemeinsamer Speicher")
            row("memorychip", "Für Modelle frei", Format.bytes(hardware.modelBudgetBytes))
            if let volume = model.modelRootVolume {
                row(volume.isInternal ? "internaldrive" : "externaldrive", volume.name, "\(Format.bytes(volume.available)) frei · Modellordner")
            } else {
                row("externaldrive.badge.questionmark", "Modellordner", library.rootReachable ? "–" : "nicht gewählt oder nicht verbunden")
            }
            row(network.isOnline ? "wifi" : "wifi.slash", network.isOnline ? "Online" : "Offline", "Chats bleiben immer auf dem Mac")
            row("square.stack.3d.up", "\(model.usableModels.count) Modelle bereit", runtime.loaded.isEmpty ? "keins geladen" : "\(runtime.loaded.count) geladen")
        }
        .lokiCard()
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Loki.accentText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail).font(.lokiCaption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Erste Schritte: Speicherort wählen, Startmodell laden
struct FirstStepsCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Erste Schritte").font(.lokiTitle2)
                Spacer()
                Badge(text: "2 Schritte", tint: Loki.accentText)
            }
            step(1, done: settings.modelRoot != nil && library.rootReachable,
                 title: "Speicherort für Modelle wählen",
                 detail: storage.externalVolumes.first.map { "Empfehlung: \($0.name) (\(Format.bytes($0.available)) frei) – große Modelle belasten so nicht die interne SSD." }
                    ?? "Kein externes Laufwerk erkannt. Du kannst die SSD später anschließen und den Ordner ändern.") {
                Button("Wählen …") { model.tab = .models }
                    .buttonStyle(.glass)
            }
            let starter = Catalog.descriptor(for: Catalog.starterID)!
            step(2, done: !model.usableModels.isEmpty,
                 title: "Startmodell laden: \(starter.name)",
                 detail: "Rund \(Format.bytes(starter.approxBytes)), Apache 2.0. Danach antwortet LOKI ohne Internet.") {
                if let state = library.downloads[starter.id] {
                    LokiProgressBar(value: state.fraction).frame(width: 140)
                } else {
                    Button("Laden") { model.download(starter.id) }
                        .buttonStyle(.glassProminent)
                        .tint(Loki.accent)
                        .disabled(settings.modelRoot == nil || !library.rootReachable)
                }
            }
        }
        .lokiCard()
    }

    private func step<Action: View>(_ number: Int, done: Bool, title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Loki.success.opacity(0.18) : Loki.accent.opacity(0.14))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Loki.success)
                } else {
                    Text("\(number)").font(.system(size: 14, weight: .bold)).foregroundStyle(Loki.accentText)
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.lokiHeadline)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done { action() }
        }
    }
}
