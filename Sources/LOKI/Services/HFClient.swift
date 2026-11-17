import Foundation

/// Datei in einem Hugging-Face-Repository
struct HFFile: Decodable, Hashable, Sendable {
    var type: String
    var path: String
    var size: Int64?
    var lfs: LFS?

    struct LFS: Decodable, Hashable, Sendable { var size: Int64? }

    var bytes: Int64 { lfs?.size ?? size ?? 0 }
}

enum HFError: LocalizedError {
    case badRepository(String)
    case http(Int, String)
    case noWeights(String)
    case notEnoughSpace(needed: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .badRepository(let id): return "„\(id)“ ist keine gültige Hugging-Face-Kennung (Format: name/modell)."
        case .http(let code, let what):
            if code == 401 || code == 403 { return "Kein Zugriff auf \(what). Das Modell ist vermutlich zugangsbeschränkt." }
            if code == 404 { return "\(what) wurde auf Hugging Face nicht gefunden." }
            return "Hugging Face antwortet mit Fehler \(code) für \(what)."
        case .noWeights(let id): return "\(id) enthält keine MLX-Gewichte (.safetensors)."
        case .notEnoughSpace(let needed, let available):
            return "Zu wenig Platz: nötig \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)), frei \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))."
        }
    }
}

/// Zugriff auf Hugging Face – nur für Modell-Downloads, die der Nutzer selbst startet.
enum HFClient {
    static let host = URL(string: "https://huggingface.co")!

    /// Dateien, die für ein MLX-Modell nötig sind
    static func isNeeded(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name.hasPrefix(".") { return false }
        if path.contains("/") && !path.hasPrefix("tokenizer") { return false } // keine Unterordner (z. B. „original/“)
        if name.hasSuffix(".safetensors") { return true }
        if name.hasSuffix(".json") { return true }
        if name.hasSuffix(".jinja") { return true }
        if name == "tokenizer.model" || name.hasSuffix(".tiktoken") || name == "merges.txt" || name == "vocab.txt" { return true }
        return false
    }

    static func validate(_ id: String) throws -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://huggingface.co/", with: "")
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { throw HFError.badRepository(id) }
        return trimmed
    }

    static func listFiles(_ id: String) async throws -> [HFFile] {
        let repo = try validate(id)
        var components = URLComponents(url: host.appendingPathComponent("api/models/\(repo)/tree/main"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw HFError.http(code, repo) }
        let files = try JSONDecoder().decode([HFFile].self, from: data).filter { $0.type == "file" && isNeeded($0.path) }
        guard files.contains(where: { $0.path.hasSuffix(".safetensors") }) else { throw HFError.noWeights(repo) }
        return files
    }

    static func fileURL(repo: String, path: String) -> URL {
        let escaped = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repo)/resolve/main/\(escaped)")!
    }
}

/// Lädt eine Datei direkt auf das Ziel-Laufwerk (keine Zwischenkopie auf der internen SSD) und setzt
/// abgebrochene Downloads über HTTP-Range fort.
final class FileFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let source: URL
    private let destination: URL
    private let partial: URL
    private let onProgress: @Sendable (Int64) -> Void
    private var handle: FileHandle?
    private var offset: Int64 = 0
    private var written: Int64 = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let lock = NSLock()
    private var failure: Error?

    init(source: URL, destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.source = source
        self.destination = destination
        self.partial = destination.appendingPathExtension("partial")
        self.onProgress = onProgress
    }

    func run() async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size]) as? NSNumber {
            offset = size.int64Value
        } else {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                continuation = cont
                lock.unlock()
                var request = URLRequest(url: source)
                request.timeoutInterval = 60
                if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            failure = HFError.http(code, source.lastPathComponent)
            completionHandler(.cancel)
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: partial)
            if http.statusCode == 200 && offset > 0 {
                // Server ignoriert Range: von vorn beginnen
                try handle.truncate(atOffset: 0)
                offset = 0
            }
            try handle.seekToEnd()
            self.handle = handle
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            written += Int64(data.count)
            onProgress(offset + written)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        session.finishTasksAndInvalidate()
        var result: Error? = failure ?? error
        if result == nil {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: partial, to: destination)
            } catch {
                result = error
            }
        }
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        if let result { cont?.resume(throwing: result) } else { cont?.resume() }
    }
}
