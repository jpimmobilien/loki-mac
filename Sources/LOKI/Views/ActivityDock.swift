import SwiftUI
import AppKit
import LokiCore

/// Schwebende Aufgabenleiste: was LOKI gerade tut, welches Modell geladen ist, Speicher und Netz.
struct ActivityDock: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runtime: ModelRuntime
    @EnvironmentObject private var hardware: HardwareMonitor
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var library: ModelLibrary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            HStack(spacing: 14) {
                ring(progress: progress(at: timeline.date))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.lokiHeadline).lineLimit(1)
                    Text(subtitle(at: timeline.date))
                        .font(.lokiCaption)
                        .foregroundStyle(Loki.accentText)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                memory
                networkPill
                if model.isGenerating {
                    Button { model.stop() } label: {
                        Label("Stopp", systemImage: "stop.fill").font(.lokiCallout)
                    }
                    .buttonStyle(.glass)
                } else if !runtime.loaded.isEmpty {
                    Button { runtime.unloadAll(); hardware.refresh() } label: {
                        Label("Entladen", systemImage: "eject").font(.lokiCallout)
                    }
                    .buttonStyle(.glass)
                    .help("Alle Modelle aus dem Arbeitsspeicher entfernen")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 860)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Loki.Radius.dock, style: .continuous))
    }

    private var activeDownload: DownloadState? {
        library.downloads.values.first { if case .failed = $0.phase { return false } else { return true } }
    }

    private var title: String {
        switch runtime.activity {
        case .loading(let name, _, _): return "Lädt \(name)"
        case .generating(let name, _, _): return "Antwortet mit \(name)"
        case .idle:
            if let d = activeDownload { return "Lädt herunter: \(d.name)" }
            return "Bereit"
        }
    }

    private func subtitle(at date: Date) -> String {
        switch runtime.activity {
        case .loading(_, let estimate, let started):
            let elapsed = date.timeIntervalSince(started)
            if let estimate { return "\(Format.seconds(elapsed)) von etwa \(Format.seconds(estimate)) · aus dem Modellordner" }
            return "\(Format.seconds(elapsed)) · aus dem Modellordner"
        case .generating(_, let tokens, let tps):
            return tokens > 0 ? "\(tokens) Token · \(Format.tokensPerSecond(tps)) · lokal" : "Liest den Kontext ein · lokal"
        case .idle:
            if let d = activeDownload {
                switch d.phase {
                case .listing: return "Dateiliste wird abgefragt …"
                case .finishing: return "Wird geprüft …"
                default:
                    let speed = d.bytesPerSecond > 0 ? " · \(Format.speed(d.bytesPerSecond))" : ""
                    return "\(Format.bytes(d.doneBytes)) von \(Format.bytes(d.totalBytes))\(speed)"
                }
            }
            let names = runtime.loaded.values.map(\.name).sorted()
            if !names.isEmpty { return "\(names.joined(separator: ", ")) geladen · alles lokal" }
            let count = model.usableModels.count
            if count == 0 { return library.rootReachable || model.settings.modelRoot == nil ? "Noch kein Modell installiert" : "Modell-Laufwerk nicht verbunden" }
            return "\(count) \(count == 1 ? "Modell" : "Modelle") installiert · keins geladen"
        }
    }

    private func progress(at date: Date) -> Double? {
        switch runtime.activity {
        case .loading(_, let estimate, let started):
            guard let estimate, estimate > 0 else { return nil }
            return min(0.95, date.timeIntervalSince(started) / estimate)
        case .generating: return nil
        case .idle:
            if let d = activeDownload, d.totalBytes > 0 { return d.fraction }
            return runtime.loaded.isEmpty ? 0 : 1
        }
    }

    private func ring(progress: Double?) -> some View {
        ZStack {
            Circle().stroke(Loki.well, lineWidth: 3)
            if let progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [Loki.accent, Loki.progressEnd, Loki.accent], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Loki.accent.opacity(0.4), radius: 3)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Loki.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) * 300))
            }
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .frame(width: 42, height: 42)
    }

    private var memory: some View {
        let total = hardware.physicalMemory
        let used = total > hardware.availableMemory ? total - hardware.availableMemory : 0
        return VStack(alignment: .trailing, spacing: 4) {
            Text("Speicher \(Format.bytes(used)) / \(Format.bytes(total))")
                .font(.lokiCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            MeterBar(fraction: hardware.usedFraction)
                .frame(width: 130)
        }
        .help("Arbeitsspeicher. Davon durch geladene Modelle belegt: \(Format.bytes(hardware.mlxActiveMemory))")
    }

    private var networkPill: some View {
        HStack(spacing: 6) {
            StatusDot(color: network.isOnline ? Loki.success : Loki.warning)
            Text(network.isOnline ? "Online" : "Offline").font(.lokiCaption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Loki.well))
        .help(network.isOnline
              ? "Internet wird nur für Modell-Downloads genutzt, die du startest. Chats bleiben auf dem Mac."
              : "Offline: Chat und alle installierten Modelle funktionieren weiter. Downloads sind nicht möglich.")
    }
}
