import SwiftUI
import AppKit
import LokiCore

struct ModelsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var runtime: ModelRuntime
    @EnvironmentObject private var hardware: HardwareMonitor
    @State private var filter = ""
    @State private var customID = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.isQAMode { DemoBadge() }
                StorageCard()
                if !library.downloads.isEmpty { downloads }
                installedSection
                addCustom
                catalogSection
            }
            .frame(maxWidth: 1080)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 140)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Modelle").font(.lokiTitle)
            Text("\(library.installed.count) installiert · \(runtime.loaded.count) geladen · \(Format.bytes(hardware.modelBudgetBytes)) frei für Modelle")
                .font(.lokiCallout)
                .foregroundStyle(.secondary)
            Spacer()
            TextField("Katalog durchsuchen", text: $filter)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(width: 220)
                .glassEffect(.regular, in: Capsule())
        }
    }

    // MARK: Downloads

    private var downloads: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Downloads")
            ForEach(library.downloads.values.sorted { $0.startedAt < $1.startedAt }) { state in
                HStack(spacing: 14) {
                    IconTile(systemImage: "arrow.down.circle", tint: Loki.accent, size: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(state.name).font(.lokiHeadline)
                            Spacer()
                            Text(downloadText(state)).font(.lokiCaption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if case .failed(let message) = state.phase {
                            Text(message).font(.system(size: 12.5)).foregroundStyle(Loki.danger)
                        } else {
                            LokiProgressBar(value: state.fraction)
                        }
                    }
                    if case .failed = state.phase {
                        Button("Erneut") { model.download(state.id, name: state.name) }.buttonStyle(.glass)
                        Button("Schließen") { library.dismissDownload(state.id) }.buttonStyle(.glass)
                    } else {
                        Button("Anhalten") { library.cancelDownload(state.id) }.buttonStyle(.glass)
                    }
                }
                .lokiCard(padding: 14)
            }
        }
    }

    private func downloadText(_ state: DownloadState) -> String {
        switch state.phase {
        case .listing: return "Dateiliste …"
        case .finishing: return "Prüfen …"
        case .failed: return "Fehler"
        case .downloading:
            var text = "\(Format.bytes(state.doneBytes)) von \(Format.bytes(state.totalBytes))"
            if state.bytesPerSecond > 0 {
                text += " · \(Format.speed(state.bytesPerSecond))"
                let rest = Double(state.totalBytes - state.doneBytes) / state.bytesPerSecond
                text += " · noch \(Format.seconds(rest))"
            }
            return text
        }
    }

    // MARK: Installiert

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Installiert", detail: library.installed.isEmpty ? nil : Format.bytes(library.installed.reduce(Int64(0)) { $0 + $1.bytes }))
            if library.installed.isEmpty {
                Text(model.settings.modelRoot == nil
                     ? "Wähle oben einen Speicherort und lade dann ein Modell aus dem Katalog."
                     : "Noch keine Modelle im Modellordner. Unten im Katalog findest du passende Modelle für deinen Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                ForEach(library.installed) { item in
                    InstalledCard(item: item)
                }
            }
        }
    }

    // MARK: Eigenes Modell

    private var addCustom: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Modell von Hugging Face hinzufügen")
            Text("Jedes MLX-Modell lässt sich laden – die Liste unten ist nur ein Startkatalog. Gib die Kennung ein, z. B. „mlx-community/Qwen3-4B-4bit“. LOKI prüft Größe und Architektur und zeigt die Lizenz aus der Modellkarte.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("anbieter/modellname", text: $customID)
                    .textFieldStyle(.plain)
                    .font(.lokiMono)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .lokiWell()
                    .onSubmit(addCustomModel)
                Button("Laden", action: addCustomModel)
                    .buttonStyle(.glassProminent)
                    .tint(Loki.accent)
                    .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty || model.settings.modelRoot == nil)
            }
        }
        .lokiCard()
    }

    private func addCustomModel() {
        let id = customID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        model.download(id)
        customID = ""
    }

    // MARK: Katalog

    private var filteredCatalog: [ModelDescriptor] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !f.isEmpty else { return library.catalog }
        return library.catalog.filter {
            $0.name.lowercased().contains(f) || $0.family.lowercased().contains(f) || $0.publisher.lowercased().contains(f)
                || $0.license.name.lowercased().contains(f)
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Katalog", detail: "Open-Weight- und Open-Source-Modelle für MLX")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                ForEach(filteredCatalog) { descriptor in
                    CatalogCard(descriptor: descriptor)
                }
            }
        }
    }
}

private func familyTint(_ family: String) -> Color {
    switch family {
    case "Qwen": return Loki.accent
    case "Gemma": return Loki.sage
    case "Mistral", "Llama": return Loki.sand
    default: return Loki.steel
    }
}

struct CatalogCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var network: NetworkMonitor
    var descriptor: ModelDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemImage: "cpu", tint: familyTint(descriptor.family), size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.name).font(.lokiHeadline)
                    Text("\(descriptor.publisher) · \(descriptor.paramsText)").font(.lokiCaption).foregroundStyle(.secondary)
                }
                Spacer()
                if library.isInstalled(descriptor.id) {
                    Badge(text: "Installiert", systemImage: "checkmark", tint: Loki.success)
                }
            }
            Text(descriptor.summary)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                Badge(text: descriptor.openness.title, tint: descriptor.openness == .openSource ? Loki.sage : Loki.steel)
                    .help(descriptor.openness.explanation)
                Badge(text: descriptor.license.name, tint: descriptor.license.licenseClass == .free ? Loki.sage : Loki.warning)
                    .help(descriptor.license.licenseClass.title + (descriptor.license.note.map { " – \($0)" } ?? ""))
            }
            HStack(spacing: 6) {
                Badge(text: "≈ \(Format.bytes(descriptor.approxBytes))", systemImage: "internaldrive")
                Badge(text: "\(Format.contextTokens(descriptor.contextTokens)) Kontext", systemImage: "text.alignleft")
                if descriptor.supportsThinking { Badge(text: "Denkmodus", systemImage: "brain") }
            }
            fitLine
            HStack {
                Text(descriptor.capabilities.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: " · "))
                    .font(.lokiCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                action
            }
        }
        .lokiCard()
        .hoverLift(2)
    }

    private var fitLine: some View {
        let fits = Router.fits(bytes: descriptor.approxBytes, budget: Int64(Double(hardware.physicalMemory) * 0.75))
        let fitsNow = Router.fits(bytes: descriptor.approxBytes, budget: hardware.modelBudgetBytes)
        return HStack(spacing: 6) {
            Image(systemName: fits ? (fitsNow ? "checkmark.circle" : "clock") : "exclamationmark.triangle")
            Text(fits ? (fitsNow ? "Passt in den Speicher" : "Passt, wenn andere Apps Speicher freigeben") : "Zu groß für diesen Mac")
        }
        .font(.lokiCaption)
        .foregroundStyle(fits ? (fitsNow ? Loki.success : Loki.warning) : Loki.danger)
    }

    @ViewBuilder
    private var action: some View {
        if descriptor.license.blockedInEU {
            Badge(text: "In der EU gesperrt", systemImage: "nosign", tint: Loki.danger)
        } else if library.isInstalled(descriptor.id) {
            EmptyView()
        } else if let state = library.downloads[descriptor.id], !isFailed(state) {
            HStack(spacing: 8) {
                LokiProgressBar(value: state.fraction).frame(width: 90)
                Button { library.cancelDownload(descriptor.id) } label: { Image(systemName: "pause.fill") }
                    .buttonStyle(.glass)
                    .help("Anhalten")
            }
        } else {
            Button {
                model.download(descriptor.id, name: descriptor.name)
            } label: {
                Label("Laden", systemImage: "arrow.down")
            }
            .buttonStyle(.glassProminent)
            .tint(Loki.accent)
            .disabled(model.settings.modelRoot == nil || !library.rootReachable || !network.isOnline)
            .help(!network.isOnline ? "Offline – Download nicht möglich" : (model.settings.modelRoot == nil ? "Bitte zuerst einen Speicherort wählen" : "Auf \(model.modelRootVolume?.name ?? "den Modellordner") laden"))
        }
    }

    private func isFailed(_ state: DownloadState) -> Bool {
        if case .failed = state.phase { return true }
        return false
    }
}

struct InstalledCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var runtime: ModelRuntime
    @EnvironmentObject private var hardware: HardwareMonitor
    var item: InstalledModel
    @State private var confirmTrash = false
    @State private var busy = false

    var body: some View {
        let loaded = runtime.loaded[item.id]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemImage: loaded != nil ? "bolt.fill" : "cpu", tint: loaded != nil ? Loki.accent : familyTint(item.descriptor.family), size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.descriptor.name).font(.lokiHeadline)
                    Text(item.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !item.isAvailable {
                    Badge(text: "Laufwerk fehlt", systemImage: "externaldrive.badge.xmark", tint: Loki.warning)
                } else if let loaded {
                    Badge(text: "Geladen · \(Format.seconds(loaded.loadSeconds))", systemImage: "bolt.fill", tint: Loki.accentText)
                }
            }
            HStack(spacing: 6) {
                Badge(text: Format.bytes(item.bytes), systemImage: "internaldrive")
                Badge(text: item.descriptor.license.name, tint: item.descriptor.license.licenseClass == .free ? Loki.sage : Loki.warning)
                if let speed = model.settings.measuredSpeed[item.id] {
                    Badge(text: Format.tokensPerSecond(speed), systemImage: "speedometer")
                }
            }
            if !item.isSupported {
                Label("Architektur „\(item.modelType ?? "unbekannt")“ wird von LOKI 0.1 noch nicht unterstützt.", systemImage: "exclamationmark.triangle")
                    .font(.lokiCaption)
                    .foregroundStyle(Loki.warning)
            }
            HStack(spacing: 8) {
                if loaded != nil {
                    Button("Entladen") { runtime.unload(item.id); hardware.refresh() }.buttonStyle(.glass)
                } else {
                    Button {
                        Task { await load() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) } else { Text("Laden") }
                    }
                    .buttonStyle(.glass)
                    .disabled(!item.isAvailable || !item.isSupported || busy || item.isDemo)
                }
                Button("Im Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.directory]) }
                    .buttonStyle(.glass)
                    .disabled(!item.isAvailable || item.isDemo)
                Spacer()
                Button(role: .destructive) { confirmTrash = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.glass)
                    .disabled(!item.isAvailable || item.isDemo || loaded != nil)
                    .help("In den Papierkorb legen")
            }
        }
        .lokiCard()
        .confirmationDialog("\(item.descriptor.name) in den Papierkorb legen?", isPresented: $confirmTrash) {
            Button("In den Papierkorb", role: .destructive) {
                do { try library.moveToTrash(item.id) } catch { model.toast = error.localizedDescription }
            }
        } message: {
            Text("\(Format.bytes(item.bytes)) werden frei, sobald du den Papierkorb leerst.")
        }
    }

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            try await runtime.ensureLoaded(item, maxLoaded: model.settings.maxLoadedModels, budget: hardware.modelBudgetBytes, readSpeed: model.readSpeedForRoot)
            hardware.refresh()
        } catch {
            model.toast = "\(item.descriptor.name) konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }
}

/// Speicherort der Modelle: Laufwerk, freier Platz, gemessene Geschwindigkeit
struct StorageCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var storage: StorageManager
    @EnvironmentObject private var library: ModelLibrary
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Speicherort").font(.lokiTitle2)
                Spacer()
                Button("Ordner wählen …", action: chooseFolder).buttonStyle(.glass)
            }
            if let root = settings.modelRoot {
                configured(root)
            } else {
                unconfigured
            }
        }
        .lokiCard()
    }

    private func configured(_ root: URL) -> some View {
        let volume = model.modelRootVolume
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                IconTile(systemImage: (volume?.isInternal ?? false) ? "internaldrive" : "externaldrive", tint: library.rootReachable ? Loki.accent : Loki.warning, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(volume?.name ?? root.lastPathComponent).font(.lokiHeadline)
                        if library.rootReachable {
                            Badge(text: volume?.kindText ?? "Verbunden", tint: Loki.success)
                        } else {
                            Badge(text: "Nicht verbunden", systemImage: "exclamationmark.triangle", tint: Loki.warning)
                        }
                    }
                    Text(root.path).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            if let volume, library.rootReachable {
                VStack(alignment: .leading, spacing: 6) {
                    MeterBar(fraction: volume.usedFraction, height: 8)
                    HStack {
                        Text("\(Format.bytes(volume.available)) frei von \(Format.bytes(volume.total))").font(.lokiCaption)
                        if !volume.format.isEmpty { Text("· \(volume.format)").font(.lokiCaption).foregroundStyle(.secondary) }
                        Spacer()
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "speedometer").foregroundStyle(Loki.accentText)
                    if storage.measuring {
                        ProgressView().controlSize(.small)
                        Text("Messe Lesegeschwindigkeit …").font(.system(size: 12.5))
                    } else if let speed = settings.driveReadSpeed[volume.id] {
                        Text(StorageManager.interpret(speed)).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Noch nicht gemessen. Die Lesegeschwindigkeit bestimmt, wie schnell große Modelle laden.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Messen") { Task { await model.measureDriveSpeed() } }
                        .buttonStyle(.glass)
                        .disabled(storage.measuring)
                    Button("Im Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                        .buttonStyle(.glass)
                }
                if volume.format.localizedCaseInsensitiveContains("exfat") || volume.format.localizedCaseInsensitiveContains("fat") {
                    Label("Das Laufwerk ist als \(volume.format) formatiert. Für Modelle ist APFS robuster, wenn das Kabel einmal unerwartet getrennt wird. Formatieren löscht alle Daten – LOKI formatiert nie selbst.", systemImage: "info.circle")
                        .font(.lokiCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if !library.rootReachable {
                Text("Schließe das Laufwerk wieder an. LOKI erkennt es automatisch und gibt die Modelle ohne Neustart frei.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Text("Große Modelle liegen vollständig hier. Auf der internen SSD bleiben nur App, Chats und Einstellungen.")
                .font(.lokiCaption)
                .foregroundStyle(.tertiary)
        }
    }

    private var unconfigured: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Noch kein Speicherort gewählt. Empfohlen ist ein externes Laufwerk, damit große Modelle die interne SSD nicht belasten.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            ForEach(storage.externalVolumes) { volume in
                HStack(spacing: 12) {
                    IconTile(systemImage: "externaldrive", tint: Loki.accent, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.name).font(.system(size: 13.5, weight: .semibold))
                        Text("\(Format.bytes(volume.available)) frei von \(Format.bytes(volume.total)) · \(volume.format)").font(.lokiCaption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Hier speichern") {
                        model.chooseModelRoot(volume.url.appendingPathComponent("LOKI", isDirectory: true))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Loki.accent)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Loki.surface))
            }
            if storage.externalVolumes.isEmpty {
                Label("Kein externes Laufwerk erkannt. Schließe deine SSD an – sie erscheint hier automatisch.", systemImage: "externaldrive.badge.questionmark")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Button("Interne SSD verwenden") {
                model.chooseModelRoot(AppPaths.dataDirectory.appendingPathComponent("Modelle-intern", isDirectory: true))
            }
            .buttonStyle(.glass)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Als Modellordner verwenden"
        panel.message = "Wähle den Ordner für LOKI-Modelle – am besten auf deiner externen SSD."
        if let suggested = storage.externalVolumes.first?.url { panel.directoryURL = suggested }
        if panel.runModal() == .OK, let url = panel.url {
            model.chooseModelRoot(url)
        }
    }
}
