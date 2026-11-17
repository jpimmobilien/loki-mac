import SwiftUI
import AppKit
import LokiCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var runtime: ModelRuntime
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Einstellungen").font(.lokiTitle)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    autoCard
                    memoryCard
                    privacyCard
                    expertsCard
                    appearanceCard
                    aboutCard
                }
            }
            .frame(maxWidth: 1080)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconTile(systemImage: icon, tint: Loki.accent, size: 32)
                Text(title).font(.lokiTitle2)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .lokiCard()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var autoCard: some View {
        card("AUTO MODE", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gewichtung").font(.lokiCallout)
                Picker("Gewichtung", selection: $settings.preference) {
                    ForEach(RouterPreference.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                note("LOKI bewertet jedes installierte Modell nach gemessener Qualität für die Aufgabenart, Tempo, Ladezeit von deinem Laufwerk und Speicherlast. Gewechselt wird nur an Schrittgrenzen und nur, wenn es mindestens 15 % besser ist.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Neue Chats starten in").font(.lokiCallout)
                Picker("Neue Chats", selection: $settings.defaultMode) {
                    ForEach(RouterMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            Toggle(isOn: $settings.allowSwitchInManual) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Im manuellen Modus Wechsel vorschlagen").font(.system(size: 13, weight: .semibold))
                    note("Fehlt deinem Modell eine Fähigkeit, schlägt LOKI ein anderes vor. Gewechselt wird nur, wenn du klickst – nie heimlich.")
                }
            }
            .toggleStyle(.switch)
            Toggle("Gedankengang standardmäßig aufklappen", isOn: $settings.thinkingVisible)
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private var memoryCard: some View {
        card("Arbeitsspeicher", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(hardware.chipName).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Format.bytes(hardware.physicalMemory)) · GPU-Budget \(Format.bytes(hardware.gpuWorkingSet))").font(.lokiCaption).foregroundStyle(.secondary)
                }
                MeterBar(fraction: hardware.usedFraction, height: 8)
                HStack {
                    Text("Frei für Modelle: \(Format.bytes(hardware.modelBudgetBytes))").font(.lokiCaption)
                    Spacer()
                    Text("Von LOKI belegt: \(Format.bytes(hardware.mlxActiveMemory))").font(.lokiCaption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Gleichzeitig geladene Modelle").font(.lokiCallout)
                Picker("Gleichzeitig", selection: $settings.maxLoadedModels) {
                    Text("1 (empfohlen)").tag(1)
                    Text("2").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                note("Vor dem Laden eines Modells entlädt LOKI andere, wenn der Speicher sonst knapp wird – auch wenn Xcode oder ein Emulator laufen.")
            }
            HStack {
                Button("Alle Modelle entladen") { runtime.unloadAll(); hardware.refresh() }
                    .buttonStyle(.glass)
                    .disabled(runtime.loaded.isEmpty)
                Button("Modellordner …") { model.tab = .models }
                    .buttonStyle(.glass)
            }
        }
    }

    private var privacyCard: some View {
        card("Datenschutz und Netzwerk", icon: "lock.shield") {
            HStack(spacing: 8) {
                StatusDot(color: network.isOnline ? Loki.success : Loki.warning)
                Text(network.isOnline ? "Online\(network.interfaceName.isEmpty ? "" : " über \(network.interfaceName)")" : "Offline").font(.system(size: 13, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Chats, Dateien und Antworten bleiben auf diesem Mac.", systemImage: "checkmark.circle")
                Label("Internet nur für Modell-Downloads, die du selbst startest.", systemImage: "checkmark.circle")
                Label("Keine automatische Cloud-Nutzung, kein Abo, keine Telemetrie.", systemImage: "checkmark.circle")
                Label("Offline funktionieren Chat und alle installierten Modelle vollständig.", systemImage: "checkmark.circle")
            }
            .font(.system(size: 13))
            .foregroundStyle(.primary)
        }
    }

    private var expertsCard: some View {
        card("Externe Experten", icon: "person.2.wave.2") {
            HStack {
                Badge(text: "geplant", tint: Loki.accentText)
                note("Kommt nach dem lokalen Kern (Priorität P6).")
            }
            ForEach(["ChatGPT (OpenAI)", "Claude (Anthropic)"], id: \.self) { provider in
                HStack {
                    Text(provider).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("nicht eingerichtet").font(.lokiCaption).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Loki.surface))
                .opacity(0.7)
            }
            note("Später: eigener API-Schlüssel im Schlüsselbund, getrennt abgerechnet. Vor jedem Senden zeigt LOKI genau, was übertragen wird, und schickt erst nach deinem Klick.")
        }
    }

    private var appearanceCard: some View {
        card("Darstellung", icon: "circle.lefthalf.filled") {
            Picker("Darstellung", selection: $settings.appearance) {
                ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            note("Liquid Glass folgt den Systemeinstellungen, auch dem Regler für die Glas-Transparenz und „Transparenz reduzieren“.")
        }
    }

    private var aboutCard: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return card("Über LOKI", icon: "info.circle") {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOKI \(version) Vorschau").font(.lokiHeadline)
                    Text("Build \(build) · macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)")
                        .font(.lokiCaption).foregroundStyle(.secondary)
                }
            }
            note("Lokale KI-Arbeitsumgebung. Inferenz mit MLX Swift LM (MIT), Tokenizer mit swift-transformers (Apache 2.0). Modelle unterliegen ihren eigenen Lizenzen – siehe Bereich Modelle.")
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var filtered: [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.conversations }
        return model.conversations.filter { conv in
            conv.title.lowercased().contains(q) || conv.messages.contains { $0.text.lowercased().contains(q) }
        }
    }

    private struct HistoryGroup: Identifiable {
        var id: String
        var items: [Conversation]
    }

    private var groups: [HistoryGroup] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        var order: [String] = []
        var map: [String: [Conversation]] = [:]
        for conv in filtered.sorted(by: { $0.updated > $1.updated }) {
            let key = formatter.string(from: conv.updated)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(conv)
        }
        return order.map { HistoryGroup(id: $0, items: map[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Verlauf").font(.lokiTitle)
                    Text("\(model.conversations.count) Chats").font(.lokiCallout).foregroundStyle(.secondary)
                    Spacer()
                    TextField("Chats durchsuchen", text: $query)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(width: 260)
                        .glassEffect(.regular, in: Capsule())
                }
                if filtered.isEmpty {
                    Text(query.isEmpty ? "Noch keine Chats." : "Nichts gefunden.")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.id) · \(group.items.count) \(group.items.count == 1 ? "Chat" : "Chats")")
                            .font(.lokiCallout)
                            .foregroundStyle(.secondary)
                        ForEach(group.items) { conv in
                            Button { model.select(conv.id) } label: {
                                HStack(spacing: 12) {
                                    IconTile(systemImage: conv.mode == .auto ? "wand.and.stars" : "cpu", tint: conv.mode == .auto ? Loki.accent : Loki.steel, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conv.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                                        Text("\(conv.messages.filter { $0.role != .notice }.count) Nachrichten · \(Set(conv.messages.compactMap(\.modelName)).sorted().joined(separator: ", "))")
                                            .font(.lokiCaption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(conv.updated, format: .dateTime.day().month().hour().minute()).font(.lokiCaption).foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Loki.surface))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.99))
                        }
                    }
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

struct PlannedView: View {
    var tab: AppTab

    private var plan: (milestone: String, items: [String]) {
        switch tab {
        case .coding:
            return ("Meilenstein M6 · agentisches Coding", [
                "Projektordner öffnen und verstehen (Codebase-Index)",
                "Plan, Änderungen als Diff, Annehmen oder Ablehnen",
                "Checkpoint vor jeder Änderung, Rückgängig per Klick",
                "Builds mit xcodebuild, swift build und ./gradlew – Erfolg nur bei echtem Exit-Code 0",
            ])
        case .documents, .presentations, .tables:
            return ("Meilenstein M8 · Office", [
                "Dokumente als DOCX und PDF",
                "Präsentationen als PPTX, optional Keynote",
                "Tabellen als XLSX mit Formeln, die nachgerechnet werden",
                "Prüfung durch Öffnen und Rendern vor der Ausgabe",
            ])
        case .studio:
            return ("Meilenstein M8 · Creative", [
                "Bilder lokal erzeugen (FLUX.2 [klein] 4B, Apache 2.0)",
                "Bilder analysieren und beschreiben",
                "Speicher nach dem Erzeugen wieder freigeben",
            ])
        case .projects:
            return ("Meilenstein M7 · Projekte", [
                "Projekte mit Status, nach Monat gruppiert",
                "Analyse, Builds und Tests pro Projekt",
                "Chats und Änderungen je Projekt",
            ])
        default:
            return ("Geplant", [])
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            IconTile(systemImage: tab.icon, tint: Loki.accent, size: 72)
            Text(tab.title).font(.lokiTitle)
            Badge(text: plan.milestone, systemImage: "calendar", tint: Loki.accentText)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.items, id: \.self) { item in
                    Label(item, systemImage: "circle.dashed")
                        .font(.system(size: 13.5))
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .lokiCard()
            Text("LOKI 0.1 konzentriert sich auf den lokalen Kern: Modelle, AUTO MODE, Modellwechsel im Chat und Offline-Betrieb.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 110)
    }
}
