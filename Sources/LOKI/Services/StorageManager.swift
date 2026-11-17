import Foundation
import AppKit
import LokiCore

struct VolumeInfo: Identifiable, Hashable {
    var id: String          // Volume-UUID, sonst Pfad
    var name: String
    var url: URL
    var isInternal: Bool
    var isEjectable: Bool
    var total: Int64
    var available: Int64
    var format: String

    var usedFraction: Double { total > 0 ? 1 - Double(available) / Double(total) : 0 }
    var kindText: String { isInternal ? "Interne SSD" : "Externes Laufwerk" }
}

/// Laufwerke, Modellordner, freier Platz und gemessene Lesegeschwindigkeit.
@MainActor
final class StorageManager: ObservableObject {
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var measuring = false
    @Published private(set) var lastMeasurementText: String?

    var onVolumesChanged: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.onVolumesChanged?()
                }
            })
        }
    }

    func refresh() {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeUUIDStringKey,
            .volumeLocalizedFormatDescriptionKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable != false else { return nil }
            let path = url.path
            // System-Hilfsvolumes ausblenden
            if path.hasPrefix("/System/Volumes") && path != "/" { return nil }
            let available = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            return VolumeInfo(
                id: v.volumeUUIDString ?? path,
                name: v.volumeName ?? url.lastPathComponent,
                url: url,
                isInternal: v.volumeIsInternal ?? (path == "/"),
                isEjectable: v.volumeIsEjectable ?? false,
                total: Int64(v.volumeTotalCapacity ?? 0),
                available: available,
                format: v.volumeLocalizedFormatDescription ?? "")
        }
        .sorted { a, b in
            if a.isInternal != b.isInternal { return !a.isInternal }
            return a.name < b.name
        }
    }

    var externalVolumes: [VolumeInfo] { volumes.filter { !$0.isInternal } }

    /// Laufwerk, auf dem ein Pfad liegt (längster passender Mount-Pfad)
    func volume(containing url: URL) -> VolumeInfo? {
        let path = url.standardizedFileURL.path
        return volumes
            .filter { path == $0.url.path || path.hasPrefix($0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/") || $0.url.path == "/" }
            .max { $0.url.path.count < $1.url.path.count }
    }

    /// Liegt der Pfad auf einem gerade verbundenen Laufwerk?
    func isReachable(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Vorschlag für den Modellordner: erstes externes Laufwerk, sonst Programmdaten auf der internen SSD
    func suggestedModelRoot() -> URL {
        if let external = externalVolumes.max(by: { $0.available < $1.available }) {
            return external.url.appendingPathComponent("LOKI", isDirectory: true)
        }
        return AppPaths.dataDirectory.appendingPathComponent("Modelle", isDirectory: true)
    }

    /// Lesegeschwindigkeit messen: liest eine große Modelldatei (oder eine eigene Testdatei) ohne Dateicache.
    func measureReadSpeed(in directory: URL) async -> Double? {
        measuring = true
        defer { measuring = false }
        let result = await Task.detached(priority: .userInitiated) { () -> Double? in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var target: URL?
            var createdTestFile = false
            if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let file as URL in enumerator where file.pathExtension == "safetensors" {
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if size > 300_000_000 { target = file; break }
                }
            }
            if target == nil {
                let test = directory.appendingPathComponent(".loki-speedtest.bin")
                guard StorageManager.writeTestFile(test, bytes: 512_000_000) else { return nil }
                target = test
                createdTestFile = true
            }
            guard let file = target else { return nil }
            let speed = StorageManager.uncachedReadSpeed(file, maxBytes: 1_000_000_000)
            if createdTestFile { try? FileManager.default.removeItem(at: file) }
            return speed
        }.value
        if let result { lastMeasurementText = Self.interpret(result) }
        return result
    }

    nonisolated static func writeTestFile(_ url: URL, bytes: Int) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let fd = open(url.path, O_WRONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        let chunk = [UInt8](repeating: 0x5A, count: 8_000_000)
        var written = 0
        while written < bytes {
            let n = chunk.withUnsafeBytes { write(fd, $0.baseAddress, chunk.count) }
            if n <= 0 { return false }
            written += n
        }
        fsync(fd)
        return true
    }

    nonisolated static func uncachedReadSpeed(_ url: URL, maxBytes: Int) -> Double? {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        let bufferSize = 8_000_000
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 4096)
        defer { buffer.deallocate() }
        let start = Date()
        var total = 0
        while total < maxBytes {
            let n = read(fd, buffer, bufferSize)
            if n <= 0 { break }
            total += n
            if Date().timeIntervalSince(start) > 6 { break }
        }
        let elapsed = Date().timeIntervalSince(start)
        guard total > 50_000_000, elapsed > 0 else { return nil }
        return Double(total) / elapsed
    }

    /// Einordnung der gemessenen Geschwindigkeit
    static func interpret(_ bytesPerSecond: Double) -> String {
        let speed = Format.speed(bytesPerSecond)
        switch bytesPerSecond {
        case ..<600e6:
            return "\(speed) – entspricht USB mit 5 Gbit/s. Ein 20-GB-Modell braucht rund \(Format.seconds(20e9 / bytesPerSecond)) zum Laden."
        case ..<1_200e6:
            return "\(speed) – entspricht USB mit 10 Gbit/s. Ein 20-GB-Modell braucht rund \(Format.seconds(20e9 / bytesPerSecond)) zum Laden."
        default:
            return "\(speed) – Thunderbolt-, USB4- oder interne Geschwindigkeit. Ein 20-GB-Modell lädt in rund \(Format.seconds(20e9 / bytesPerSecond))."
        }
    }
}

/// Feste Orte für App-Daten (im Prüfmodus über LOKI_DATA_DIR umgelenkt)
enum AppPaths {
    static var dataDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["LOKI_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LOKI", isDirectory: true)
    }

    static var conversationsFile: URL { dataDirectory.appendingPathComponent("chats.json") }
}
