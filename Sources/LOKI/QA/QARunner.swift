import SwiftUI
import AppKit
import MLX
import LokiCore

/// Prüfmodus für die CI (nur mit eigenem Datenordner LOKI_DATA_DIR):
///
///   LOKI --snapshot <Ordner>      Vorschaubilder aller Bereiche in Dunkel und Hell (mit markierten Demo-Daten)
///   LOKI --selftest <Ordner> [--catalog-check] [--download <hf-id>]
///                                  echte Systemwerte, Katalogprüfung bei Hugging Face, echter Download mit dem
///                                  App-Downloader, Laden mit MLX, zwei Chat-Antworten über Router und Context Engine
@MainActor
enum QARunner {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--selftest")
    }

    static func argument(_ name: String) -> String? {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
        return nil
    }

    static func run(model: AppModel) async {
        if let out = argument("--snapshot") {
            await snapshots(model: model, out: URL(fileURLWithPath: out, isDirectory: true))
        } else if let out = argument("--selftest") {
            await selftest(model: model, out: URL(fileURLWithPath: out, isDirectory: true))
        }
        fflush(stdout)
        NSApp.terminate(nil)
    }

    // MARK: - Vorschaubilder

    static func snapshots(model: AppModel, out: URL) async {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        QADemo.populate(model)
        var manifest: [[String: String]] = []
        guard let window = mainWindow() else {
            print("[Snapshot] kein Fenster gefunden")
            return
        }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let shots: [(String, @MainActor () -> Void)] = [
            ("01-home", { model.tab = .home }),
            ("02-chat-auto-wechsel", { model.select(QADemo.chatAutoID) }),
            ("03-chat-manuell", { model.select(QADemo.chatManualID) }),
            ("04-modelle", { model.tab = .models }),
            ("05-einstellungen", { model.tab = .settings }),
            ("06-verlauf", { model.tab = .history }),
            ("07-coding-geplant", { model.tab = .coding }),
            ("08-neuer-chat", { model.newConversation() }),
        ]
        for appearance in [AppearanceChoice.dark, .light] {
            model.settings.appearance = appearance
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            for (name, prepare) in shots {
                prepare()
                try? await Task.sleep(nanoseconds: 900_000_000)
                let file = "\(name)-\(appearance == .dark ? "dunkel" : "hell").png"
                let method = capture(window, to: out.appendingPathComponent(file))
                manifest.append(["file": file, "method": method])
                print("[Snapshot] \(file) (\(method))")
            }
        }
        model.settings.appearance = .system
        let info: [String: Any] = [
            "images": manifest,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "chip": model.hardware.chipName,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("manifest.json"))
        }
        print("[Snapshot] fertig: \(manifest.count) Bilder")
    }

    static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeKey } ?? NSApp.windows.first
    }

    /// Fensterbild über den WindowServer (mit echtem Glas), sonst die Ansicht selbst
    static func capture(_ window: NSWindow, to url: URL) -> String {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: CreateImage.self)
            if let image = fn(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue(), image.width > 10 {
                let rep = NSBitmapImageRep(cgImage: image)
                if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil { return "window-server" }
            }
        }
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                return "cache-display"
            }
        }
        return "failed"
    }

    // MARK: - Selbsttest

    static func selftest(model: AppModel, out: URL) async {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var report: [String: Any] = [:]
        func log(_ text: String) { print("[Selbsttest] \(text)"); fflush(stdout) }

        // 1. Systemwerte
        model.hardware.refresh()
        report["system"] = [
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "chip": model.hardware.chipName,
            "physicalMemory": model.hardware.physicalMemory,
            "gpuWorkingSet": model.hardware.gpuWorkingSet,
            "availableMemory": model.hardware.availableMemory,
            "modelBudget": model.hardware.modelBudgetBytes,
            "online": model.network.isOnline,
            "volumes": model.storage.volumes.map { ["name": $0.name, "internal": $0.isInternal, "free": $0.available, "format": $0.format] as [String: Any] },
        ] as [String: Any]
        log("System: \(model.hardware.chipName), \(Format.bytes(model.hardware.physicalMemory)), Budget \(Format.bytes(model.hardware.modelBudgetBytes))")

        // 2. Router-Plausibilität mit dem Katalog
        let ctx = RouterContext(memoryBudgetBytes: 44_000_000_000)
        let all = Catalog.models.map { RouterCandidate(descriptor: $0) }
        var routing: [[String: String]] = []
        for prompt in [
            "Hallo!",
            "Schreibe eine freundliche E-Mail an einen Mieter wegen der Nebenkostenabrechnung.",
            "Mein Kotlin-Code in Android Studio wirft eine Exception beim Start. Hier ist der Code: ```kotlin\nfun main() {}\n```",
            "Vergleiche die Vor- und Nachteile von Miete und Kauf und begründe deine Empfehlung.",
        ] {
            let profile = TaskClassifier.classify(prompt)
            let decision = Router.decide(RouteRequest(profile: profile, mode: .auto), candidates: all, context: ctx)
            routing.append(["prompt": prompt, "kind": profile.kind.rawValue, "model": decision.modelName ?? "-", "reason": decision.reason])
            log("Router: \(profile.kind.title) → \(decision.modelName ?? "-")")
        }
        report["routing"] = routing

        // 3. Katalog bei Hugging Face prüfen (Existenz, Größe, Architektur)
        if CommandLine.arguments.contains("--catalog-check") {
            var checks: [[String: Any]] = []
            for descriptor in Catalog.models {
                var entry: [String: Any] = ["id": descriptor.id, "approxBytes": descriptor.approxBytes]
                do {
                    let files = try await HFClient.listFiles(descriptor.id)
                    let bytes = files.reduce(Int64(0)) { $0 + $1.bytes }
                    entry["bytes"] = bytes
                    entry["files"] = files.count
                    let (data, _) = try await URLSession.shared.data(from: HFClient.fileURL(repo: descriptor.id, path: "config.json"))
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let text = json["text_config"] as? [String: Any]
                        let type = (json["model_type"] as? String) ?? (text?["model_type"] as? String) ?? "?"
                        entry["modelType"] = type
                        entry["supported"] = Catalog.supportedModelTypes.contains(type)
                        entry["context"] = (json["max_position_embeddings"] as? Int) ?? (text?["max_position_embeddings"] as? Int) ?? 0
                    }
                    log("Katalog ✓ \(descriptor.id): \(Format.bytes(bytes)), \(entry["modelType"] ?? "?")")
                } catch {
                    entry["error"] = error.localizedDescription
                    log("Katalog ✗ \(descriptor.id): \(error.localizedDescription)")
                }
                checks.append(entry)
            }
            report["catalog"] = checks
        }

        // 4. Echter Download mit dem App-Downloader, Laden mit MLX, zwei Antworten im Chat
        if let repo = argument("--download") {
            let root = AppPaths.dataDirectory.appendingPathComponent("Modellordner-Test", isDirectory: true)
            model.chooseModelRoot(root)
            let startDownload = Date()
            model.download(repo)
            while let state = model.library.downloads[repo] {
                if case .failed(let message) = state.phase {
                    report["download"] = ["ok": false, "error": message] as [String: Any]
                    log("Download ✗ \(message)")
                    break
                }
                if Date().timeIntervalSince(startDownload) > 1200 { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if let installed = model.library.installedModel(repo) {
                let seconds = Date().timeIntervalSince(startDownload)
                report["download"] = ["ok": true, "bytes": installed.bytes, "seconds": seconds, "modelType": installed.modelType ?? "?", "supported": installed.isSupported] as [String: Any]
                log("Download ✓ \(Format.bytes(installed.bytes)) in \(Format.seconds(seconds))")

                if let speed = await model.storage.measureReadSpeed(in: root) {
                    report["driveReadSpeed"] = speed
                    log("Lesegeschwindigkeit: \(Format.speed(speed))")
                }

                // Chat über den echten Weg: Router → Laden → Context Engine → MLX
                model.draftMode = .auto
                model.newConversation()
                var answers: [[String: Any]] = []
                for prompt in ["Was ist die Hauptstadt von Frankreich? Antworte in einem Satz.", "Und wie viele Einwohner hat sie ungefähr?"] {
                    model.draft = prompt
                    model.send()
                    let start = Date()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    while model.isGenerating, Date().timeIntervalSince(start) < 600 {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                    let messages = model.selectedConversation?.messages ?? []
                    let answer = messages.last(where: { $0.role == .assistant })
                    let notices = messages.filter { $0.role == .notice }.map(\.text)
                    answers.append([
                        "prompt": prompt,
                        "answer": answer?.text ?? "",
                        "reasoningChars": answer?.reasoning?.count ?? 0,
                        "model": answer?.modelName ?? "-",
                        "reason": answer?.routeReason ?? "-",
                        "tokensPerSecond": answer?.stats?.tokensPerSecond ?? 0,
                        "timeToFirstToken": answer?.stats?.timeToFirstToken ?? 0,
                        "tokens": answer?.stats?.tokens ?? 0,
                        "notices": notices,
                    ])
                    log("Antwort (\(answer?.modelName ?? "-"), \(Format.tokensPerSecond(answer?.stats?.tokensPerSecond ?? 0))): \(answer?.text.prefix(160) ?? "")")
                    if !notices.isEmpty { log("Hinweise: \(notices.joined(separator: " | "))") }
                }
                report["chat"] = answers
                let before = MLX.Memory.activeMemory
                model.runtime.unloadAll()
                let after = MLX.Memory.activeMemory
                report["unload"] = ["activeBefore": before, "activeAfter": after]
                log("Entladen: \(Format.bytes(before)) → \(Format.bytes(after))")
            }
        }

        report["finished"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("selbsttest.json"))
        }
        log("fertig")
    }
}
