import SwiftUI
import AppKit
import LokiCore

/// Eingabefeld mit AUTO/Manuell-Schalter, Modellwahl, Zweitmeinung (geplant) und Senden.
struct Composer: View {
    enum Style { case home, chat }
    var style: Style

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var runtime: ModelRuntime
    @FocusState private var focused: Bool
    @State private var showExpertInfo = false

    private var radius: CGFloat { Loki.Radius.composer }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: style == .home ? 17 : 15))
                .lineLimit(style == .home ? 2...8 : 1...8)
                .focused($focused)
                .onSubmit { model.send() }
                .disabled(model.isGenerating)

            HStack(spacing: 10) {
                Picker("Modus", selection: $model.currentMode) {
                    ForEach(RouterMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help("Auto: LOKI wählt pro Anfrage das passende lokale Modell und zeigt den Grund. Manuell: dein Modell gilt für den ganzen Chat und wird nie heimlich ersetzt.")

                if model.currentMode == .manual {
                    manualMenu
                } else {
                    autoPreview
                }

                Spacer(minLength: 8)

                expertButton

                if !network.isOnline {
                    Badge(text: "Offline", systemImage: "wifi.slash", tint: Loki.warning)
                        .help("Offline: Chat mit installierten Modellen funktioniert vollständig.")
                }

                sendButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .lokiFocusRing(focused, radius: radius)
        .animation(Loki.state, value: focused)
        .onAppear { if style == .chat { focused = true } }
    }

    private var placeholder: String {
        if model.usableModels.isEmpty { return "Zuerst ein Modell laden – dann kann LOKI antworten …" }
        return style == .home ? "Frag LOKI etwas, lass einen Text schreiben oder Code erklären …" : "Nachricht an LOKI …"
    }

    private var manualMenu: some View {
        let current = model.currentManualModelID.flatMap { library.installedModel($0) }
        return Menu {
            if model.usableModels.isEmpty {
                Text("Kein Modell installiert")
            }
            ForEach(model.usableModels) { m in
                Button {
                    model.currentManualModelID = m.id
                } label: {
                    if m.id == model.currentManualModelID {
                        Label(m.descriptor.name, systemImage: "checkmark")
                    } else {
                        Text(m.descriptor.name + (runtime.isLoaded(m.id) ? " · geladen" : ""))
                    }
                }
            }
        } label: {
            Label(current?.descriptor.name ?? "Modell wählen", systemImage: "cpu")
                .font(.lokiCallout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Dieses Modell beantwortet alle Nachrichten in diesem Chat.")
    }

    @ViewBuilder
    private var autoPreview: some View {
        if let decision = model.previewDecision(for: model.draft), let name = decision.modelName, decision.modelID != nil {
            Label("AUTO wählt \(name)", systemImage: "wand.and.stars")
                .font(.lokiCallout)
                .foregroundStyle(Loki.accentText)
                .lineLimit(1)
                .help(decision.reason)
        } else {
            Label("AUTO wählt das Modell pro Anfrage", systemImage: "wand.and.stars")
                .font(.lokiCallout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var expertButton: some View {
        Button {
            showExpertInfo.toggle()
        } label: {
            Label("Zweitmeinung", systemImage: "person.2.wave.2")
                .font(.lokiCallout)
        }
        .buttonStyle(.glass)
        .help("Externe KI um Zweitmeinung bitten – geplant")
        .popover(isPresented: $showExpertInfo, arrowEdge: .top) {
            ExpertInfoView(isOnline: network.isOnline)
        }
    }

    private var sendButton: some View {
        Group {
            if model.isGenerating {
                Button { model.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .help("Antwort anhalten")
            } else {
                Button { model.send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Senden (Return)")
            }
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(Loki.accent)
        .controlSize(.large)
    }
}

/// Erklärung zu „Externe KI um Zweitmeinung bitten“ (Priorität P6)
struct ExpertInfoView: View {
    var isOnline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Externe KI um Zweitmeinung bitten").font(.lokiHeadline)
                Badge(text: "geplant", tint: Loki.accentText)
            }
            Text("Später kannst du hier ChatGPT (OpenAI) oder Claude (Anthropic) gezielt um eine zweite Meinung bitten. LOKI zeigt dir vorher genau, was gesendet wird, und schickt erst nach deiner Bestätigung. Die Antwort erscheint im selben Chat und das lokale Modell kann sie bewerten.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Label("Keine automatische Cloud-Nutzung", systemImage: "checkmark.shield")
                Label("Keine Übertragung ohne deine Auswahl", systemImage: "checkmark.shield")
                Label("Kein Abo nötig – eigene API-Schlüssel, getrennt abgerechnet", systemImage: "checkmark.shield")
            }
            .font(.lokiCallout)
            .foregroundStyle(Loki.sage)
            Text(isOnline
                 ? "In LOKI 0.1 ist diese Funktion noch nicht enthalten. LOKI sendet keine Chat-Inhalte ins Internet."
                 : "Offline nicht verfügbar. Alle lokalen Funktionen laufen weiter.")
                .font(.lokiCaption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 380)
    }
}
