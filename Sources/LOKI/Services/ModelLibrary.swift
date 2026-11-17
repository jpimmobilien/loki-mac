import Foundation
import AppKit
import LokiCore

struct InstalledModel: Identifiable, Hashable {
    var id: String
    var descriptor: ModelDescriptor
    var directory: URL
    var bytes: Int64
    var modelType: String?
    var isSupported: Bool
    /// false, wenn das Laufwerk mit dem Modell gerade nicht verbunden ist
    var isAvailable = true
    var isDemo = false
}

/// Zuletzt gesehene Modelle – damit sie bei abgezogenem Laufwerk sichtbar bleiben
struct CachedModel: Codable {
    var id: String
    var name: String
    var folder: String
    var bytes: Int64
    var modelType: String?
    var isSupported: Bool
}

struct DownloadState: Identifiable, Equatable {
    enum Phase: Equatable {
        case listing
        case downloading
        case finishing
        case failed(String)
    }
    var id: String
    var name: String
    var phase: Phase
    var totalBytes: Int64 = 0
    var doneBytes: Int64 = 0
    var startedAt = Date()
    var bytesPerSecond: Double = 0

    var fraction: Double { totalBytes > 0 ? Double(doneBytes) / Double(totalBytes) : 0 }
}

/// Manifest im Modellordner: woher das Modell kommt und ob der Download vollständig ist
struct ModelManifest: Codable {
    var id: String
    var name: String
    var files: [String]
    var bytes: Int64
    var completed: Bool
    var downloadedAt: Date?

    static let fileName = "loki-model.json"
}

/// Katalog, installierte Modelle und Downloads. Modelle liegen unter <Modellordner>/Modelle/<org>__<name>.
@MainActor
final class ModelLibrary: ObservableObject {
    @Published var catalog: [ModelDescriptor] = Catalog.models
    @Published private(set) var installed: [InstalledModel] = []
    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published private(set) var rootReachable = false
    @Published var lastMessage: String?

    private var tasks: [String: Task<Void, Never>] = [:]
    private(set) var root: URL?

    var modelsDirectory: URL? { root?.appendingPathComponent("Modelle", isDirectory: true) }

    func setRoot(_ url: URL?) {
        root = url
        rescan()
    }

    func rescan() {
        guard let dir = modelsDirectory, let root = self.root else {
            rootReachable = false
            installed = installed.filter(\.isDemo)
            return
        }
        var isDir: ObjCBool = false
        rootReachable = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) && isDir.boolValue
        let demo = installed.filter(\.isDemo)
        guard rootReachable else {
            // Laufwerk nicht verbunden: bekannte Modelle bleiben sichtbar, sind aber nicht nutzbar
            installed = loadCache().map { cached in
                var descriptor = Catalog.descriptor(for: cached.id)
                    ?? .local(id: cached.id, name: cached.name, bytes: cached.bytes, contextTokens: nil, modelType: cached.modelType)
                descriptor.approxBytes = cached.bytes
                return InstalledModel(
                    id: cached.id, descriptor: descriptor, directory: URL(fileURLWithPath: cached.folder, isDirectory: true),
                    bytes: cached.bytes, modelType: cached.modelType, isSupported: cached.isSupported, isAvailable: false)
            } + demo
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let subdirs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var found: [InstalledModel] = []
        for folder in subdirs {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let model = Self.inspect(folder) { found.append(model) }
        }
        found.sort { $0.descriptor.name.localizedCaseInsensitiveCompare($1.descriptor.name) == .orderedAscending }
        saveCache(found)
        installed = found + demo
    }

    private var cacheURL: URL { AppPaths.dataDirectory.appendingPathComponent("modelle-zuletzt.json") }

    private func saveCache(_ models: [InstalledModel]) {
        let cached = models.map {
            CachedModel(id: $0.id, name: $0.descriptor.name, folder: $0.directory.path, bytes: $0.bytes, modelType: $0.modelType, isSupported: $0.isSupported)
        }
        try? FileManager.default.createDirectory(at: AppPaths.dataDirectory, withIntermediateDirectories: true)
        try? JSONEncoder.loki.encode(cached).write(to: cacheURL)
    }

    private func loadCache() -> [CachedModel] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder.loki.decode([CachedModel].self, from: data)) ?? []
    }

    /// Liest einen Modellordner: Manifest, config.json, Größe
    nonisolated static func inspect(_ folder: URL) -> InstalledModel? {
        let fm = FileManager.default
        let config = folder.appendingPathComponent("config.json")
        guard fm.fileExists(atPath: config.path) else { return nil }
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        guard files.contains(where: { $0.pathExtension == "safetensors" }) else { return nil }
        if files.contains(where: { $0.pathExtension == "partial" }) { return nil }
        let manifestURL = folder.appendingPathComponent(ModelManifest.fileName)
        let manifest = (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder.loki.decode(ModelManifest.self, from: $0) }
        if let manifest, !manifest.completed { return nil }
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

        var modelType: String?
        var contextTokens: Int?
        if let data = try? Data(contentsOf: config), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            modelType = json["model_type"] as? String
            let text = json["text_config"] as? [String: Any]
            contextTokens = (json["max_position_embeddings"] as? Int) ?? (text?["max_position_embeddings"] as? Int)
            if modelType == nil { modelType = text?["model_type"] as? String }
        }
        let id = manifest?.id ?? "lokal/\(folder.lastPathComponent)"
        var descriptor = Catalog.descriptor(for: id)
            ?? .local(id: id, name: manifest?.name ?? folder.lastPathComponent, bytes: bytes, contextTokens: contextTokens, modelType: modelType)
        descriptor.approxBytes = bytes
        let supported = modelType.map { Catalog.supportedModelTypes.contains($0) } ?? false
        return InstalledModel(id: id, descriptor: descriptor, directory: folder, bytes: bytes, modelType: modelType, isSupported: supported)
    }

    func installedModel(_ id: String) -> InstalledModel? { installed.first { $0.id == id } }
    func isInstalled(_ id: String) -> Bool { installedModel(id) != nil }

    // MARK: Download

    func download(id rawID: String, name: String? = nil, availableSpace: Int64?) {
        guard let dir = modelsDirectory else {
            lastMessage = "Bitte zuerst in „Modelle“ einen Speicherort wählen."
            return
        }
        guard let id = try? HFClient.validate(rawID) else {
            lastMessage = HFError.badRepository(rawID).errorDescription
            return
        }
        if let existing = downloads[id] {
            if case .failed = existing.phase {
                // erneuter Versuch nach einem Fehler
            } else {
                return
            }
        }
        let displayName = name ?? Catalog.descriptor(for: id)?.name ?? (id.split(separator: "/").last.map(String.init) ?? id)
        downloads[id] = DownloadState(id: id, name: displayName, phase: .listing)
        let target = dir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "__"), isDirectory: true)

        tasks[id] = Task { [weak self] in
            do {
                let files = try await HFClient.listFiles(id)
                let total = files.reduce(Int64(0)) { $0 + $1.bytes }
                if let free = availableSpace, total + 1_000_000_000 > free {
                    throw HFError.notEnoughSpace(needed: total, available: free)
                }
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let manifest = ModelManifest(id: id, name: displayName, files: files.map(\.path), bytes: total, completed: false, downloadedAt: nil)
                try JSONEncoder.loki.encode(manifest).write(to: target.appendingPathComponent(ModelManifest.fileName))
                self?.update(id) { $0.phase = .downloading; $0.totalBytes = total; $0.startedAt = Date() }

                var done: Int64 = 0
                // kleine Dateien (Konfiguration, Tokenizer) zuerst
                for file in files.sorted(by: { $0.bytes < $1.bytes }) {
                    try Task.checkCancellation()
                    let dest = target.appendingPathComponent(file.path)
                    let existing = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value
                    if let existing, existing == file.bytes || (file.bytes == 0 && existing > 0) {
                        done += file.bytes
                        continue
                    }
                    let base = done
                    let throttle = ProgressThrottle()
                    try await FileFetch(source: HFClient.fileURL(repo: id, path: file.path), destination: dest) { written in
                        guard throttle.shouldReport() else { return }
                        Task { @MainActor in self?.progress(id, base + written) }
                    }.run()
                    done += file.bytes
                    self?.progress(id, done)
                }
                self?.update(id) { $0.phase = .finishing }
                var finished = manifest
                finished.completed = true
                finished.downloadedAt = Date()
                try JSONEncoder.loki.encode(finished).write(to: target.appendingPathComponent(ModelManifest.fileName))
                self?.downloads[id] = nil
                self?.tasks[id] = nil
                self?.rescan()
                if let model = self?.installedModel(id), !model.isSupported {
                    self?.lastMessage = "\(displayName) ist geladen, aber die Architektur „\(model.modelType ?? "?")“ unterstützt LOKI 0.1 noch nicht."
                } else {
                    self?.lastMessage = "\(displayName) ist bereit."
                }
            } catch is CancellationError {
                self?.downloads[id] = nil
                self?.tasks[id] = nil
            } catch let error as URLError where error.code == .cancelled {
                self?.downloads[id] = nil
                self?.tasks[id] = nil
            } catch {
                self?.update(id) { $0.phase = .failed(error.localizedDescription) }
                self?.tasks[id] = nil
            }
        }
    }

    func cancelDownload(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        downloads[id] = nil
        lastMessage = "Download angehalten. Bereits geladene Teile bleiben erhalten und werden beim nächsten Mal fortgesetzt."
    }

    func dismissDownload(_ id: String) { downloads[id] = nil }

    private func update(_ id: String, _ change: (inout DownloadState) -> Void) {
        guard var state = downloads[id] else { return }
        change(&state)
        downloads[id] = state
    }

    private func progress(_ id: String, _ bytes: Int64) {
        update(id) { state in
            state.doneBytes = min(bytes, max(state.totalBytes, bytes))
            let elapsed = Date().timeIntervalSince(state.startedAt)
            if elapsed > 1 { state.bytesPerSecond = Double(state.doneBytes) / elapsed }
        }
    }

    /// In den Papierkorb legen (nicht endgültig löschen)
    func moveToTrash(_ id: String) throws {
        guard let model = installedModel(id), !model.isDemo else { return }
        try FileManager.default.trashItem(at: model.directory, resultingItemURL: nil)
        rescan()
    }

    // MARK: Prüfmodus

    func injectDemo(_ models: [InstalledModel]) {
        installed = installed.filter { !$0.isDemo } + models
    }
}

/// Begrenzt Fortschrittsmeldungen auf etwa fünf pro Sekunde
final class ProgressThrottle: @unchecked Sendable {
    private var last = Date.distantPast
    private let lock = NSLock()

    func shouldReport() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(last) < 0.2 { return false }
        last = now
        return true
    }
}

extension JSONEncoder {
    static var loki: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var loki: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
