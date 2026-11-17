import Foundation

// MARK: - Aufgaben und Fähigkeiten

/// Art einer Anfrage. Der Router bewertet Modelle pro Aufgabenart, nicht pauschal nach Größe.
public enum TaskKind: String, Codable, CaseIterable, Sendable, Hashable {
    case quick
    case chat
    case writing
    case coding
    case reasoning
    case longContext
    case vision

    public var title: String {
        switch self {
        case .quick: return "Kurze Frage"
        case .chat: return "Gespräch"
        case .writing: return "Text schreiben"
        case .coding: return "Programmieren"
        case .reasoning: return "Analysieren"
        case .longContext: return "Langer Text"
        case .vision: return "Bild verstehen"
        }
    }
}

/// Fähigkeiten, die eine Aufgabe zwingend braucht oder ein Modell mitbringt.
public enum Capability: String, Codable, CaseIterable, Sendable, Hashable {
    case chat
    case coding
    case tools
    case reasoning
    case vision
    case longContext

    public var title: String {
        switch self {
        case .chat: return "Chat"
        case .coding: return "Code"
        case .tools: return "Werkzeuge"
        case .reasoning: return "Denkmodus"
        case .vision: return "Bilder"
        case .longContext: return "Langer Kontext"
        }
    }
}

// MARK: - Offenheit und Lizenz

/// Unterscheidung nach der Open Source AI Definition 1.0 der OSI:
/// „Open Source“ nur, wenn neben den Gewichten auch Code und Angaben zu den Trainingsdaten frei sind.
public enum Openness: String, Codable, Sendable, Hashable {
    case openSource
    case openWeight

    public var title: String {
        switch self {
        case .openSource: return "Open Source"
        case .openWeight: return "Open Weight"
        }
    }

    public var explanation: String {
        switch self {
        case .openSource:
            return "Gewichte, Code und Angaben zu den Trainingsdaten sind offen (OSI-Definition)."
        case .openWeight:
            return "Die Gewichte sind frei verfügbar, die Trainingsdaten aber nicht offengelegt."
        }
    }
}

public enum LicenseClass: String, Codable, Sendable, Hashable {
    case free
    case conditions
    case nonCommercial

    public var title: String {
        switch self {
        case .free: return "Frei nutzbar"
        case .conditions: return "Mit Auflagen"
        case .nonCommercial: return "Nicht kommerziell"
        }
    }
}

public struct LicenseInfo: Codable, Hashable, Sendable {
    public var name: String
    public var licenseClass: LicenseClass
    public var note: String?
    /// Lizenz schließt Personen oder Firmen mit Sitz in der EU aus – LOKI blockiert dann Download und Nutzung.
    public var blockedInEU: Bool

    public init(name: String, licenseClass: LicenseClass, note: String? = nil, blockedInEU: Bool = false) {
        self.name = name
        self.licenseClass = licenseClass
        self.note = note
        self.blockedInEU = blockedInEU
    }

    public static let apache2 = LicenseInfo(name: "Apache 2.0", licenseClass: .free)
    public static let mit = LicenseInfo(name: "MIT", licenseClass: .free)
    public static let unknown = LicenseInfo(
        name: "Unbekannt", licenseClass: .conditions, note: "Lizenz bitte in der Modellkarte prüfen.")
}

// MARK: - Modellbeschreibung

/// Beschreibung eines Modells – aus dem Katalog oder aus einem installierten Ordner abgeleitet.
public struct ModelDescriptor: Codable, Identifiable, Hashable, Sendable {
    /// Hugging-Face-Kennung, z. B. „mlx-community/Qwen3-4B-4bit“, oder „lokal/<Ordnername>“
    public var id: String
    public var name: String
    public var family: String
    public var publisher: String
    public var summary: String
    public var totalParamsB: Double
    public var activeParamsB: Double
    public var quantization: String
    /// Ungefähre Größe der Gewichte in Bytes (vor dem Download geschätzt, danach gemessen)
    public var approxBytes: Int64
    public var contextTokens: Int
    public var capabilities: Set<Capability>
    public var license: LicenseInfo
    public var openness: Openness
    /// Startwerte der Qualität je Aufgabenart (0…1). Werden durch Messungen ersetzt.
    public var quality: [TaskKind: Double]
    /// Modell kennt einen abschaltbaren Denkmodus (z. B. Qwen3)
    public var supportsThinking: Bool
    public var isCatalogEntry: Bool

    public init(
        id: String, name: String, family: String, publisher: String, summary: String,
        totalParamsB: Double, activeParamsB: Double, quantization: String = "4 Bit",
        approxBytes: Int64, contextTokens: Int, capabilities: Set<Capability>,
        license: LicenseInfo, openness: Openness = .openWeight,
        quality: [TaskKind: Double], supportsThinking: Bool = false, isCatalogEntry: Bool = true
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.publisher = publisher
        self.summary = summary
        self.totalParamsB = totalParamsB
        self.activeParamsB = activeParamsB
        self.quantization = quantization
        self.approxBytes = approxBytes
        self.contextTokens = contextTokens
        self.capabilities = capabilities
        self.license = license
        self.openness = openness
        self.quality = quality
        self.supportsThinking = supportsThinking
        self.isCatalogEntry = isCatalogEntry
    }

    public var isMixtureOfExperts: Bool { activeParamsB < totalParamsB * 0.6 }

    public var paramsText: String {
        let total = Format.params(totalParamsB)
        if isMixtureOfExperts { return "\(total) · \(Format.params(activeParamsB)) aktiv" }
        return total
    }

    public func quality(for kind: TaskKind) -> Double {
        if let q = quality[kind] { return q }
        // Rückfall: Mittelwert der bekannten Werte oder neutral
        let values = quality.values
        guard !values.isEmpty else { return 0.5 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Ordnername auf dem Datenträger: „mlx-community/Qwen3-4B-4bit“ → „mlx-community__Qwen3-4B-4bit“
    public var folderName: String { id.replacingOccurrences(of: "/", with: "__") }

    /// Beschreibung für einen Ordner, der nicht aus dem Katalog stammt.
    public static func local(
        id: String, name: String, bytes: Int64, contextTokens: Int?, modelType: String?
    ) -> ModelDescriptor {
        let paramsB = Double(bytes) / 0.56e9
        return ModelDescriptor(
            id: id, name: name, family: modelType ?? "Unbekannt", publisher: "Eigener Ordner",
            summary: "Selbst hinzugefügtes MLX-Modell. Qualitätswerte sind geschätzt, bis LOKI eigene Messwerte hat.",
            totalParamsB: paramsB, activeParamsB: paramsB, quantization: "–",
            approxBytes: bytes, contextTokens: contextTokens ?? 8192, capabilities: [.chat],
            license: .unknown, openness: .openWeight,
            quality: [:], supportsThinking: false, isCatalogEntry: false)
    }
}
