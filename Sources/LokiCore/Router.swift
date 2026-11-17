import Foundation

public enum RouterMode: String, Codable, CaseIterable, Sendable {
    case auto
    case manual

    public var title: String { self == .auto ? "Auto" : "Manuell" }
}

/// Gewichtung des Routers: Schnell, Ausgewogen oder Beste Qualität.
public enum RouterPreference: String, Codable, CaseIterable, Sendable {
    case fast
    case balanced
    case best

    public var title: String {
        switch self {
        case .fast: return "Schnell"
        case .balanced: return "Ausgewogen"
        case .best: return "Beste Qualität"
        }
    }

    /// Gewichte für Qualität, Tempo, Ladezeit und Speicherlast
    public var weights: (quality: Double, tempo: Double, load: Double, memory: Double) {
        switch self {
        case .fast: return (0.35, 0.40, 0.20, 0.05)
        case .balanced: return (0.55, 0.20, 0.20, 0.05)
        case .best: return (0.80, 0.05, 0.10, 0.05)
        }
    }
}

/// Ein installiertes Modell aus Sicht des Routers.
public struct RouterCandidate: Sendable {
    public var descriptor: ModelDescriptor
    /// installiert und das Laufwerk ist verbunden
    public var isAvailable: Bool
    public var isLoaded: Bool
    /// gemessene Größe auf dem Datenträger
    public var bytes: Int64
    public var measuredTokensPerSecond: Double?
    public var measuredQuality: [TaskKind: Double]

    public init(
        descriptor: ModelDescriptor, isAvailable: Bool = true, isLoaded: Bool = false, bytes: Int64? = nil,
        measuredTokensPerSecond: Double? = nil, measuredQuality: [TaskKind: Double] = [:]
    ) {
        self.descriptor = descriptor
        self.isAvailable = isAvailable
        self.isLoaded = isLoaded
        self.bytes = bytes ?? descriptor.approxBytes
        self.measuredTokensPerSecond = measuredTokensPerSecond
        self.measuredQuality = measuredQuality
    }
}

/// Live-Werte des Rechners für die Entscheidung.
public struct RouterContext: Sendable {
    /// Speicher, den ein Modell belegen darf (Systemreserve und laufende Apps schon abgezogen)
    public var memoryBudgetBytes: Int64
    /// gemessene Lesegeschwindigkeit des Modell-Laufwerks
    public var readBytesPerSecond: Double
    /// Speicherbandbreite des Chips (M5 Pro: 307 GB/s)
    public var memoryBandwidthBytesPerSecond: Double

    public init(memoryBudgetBytes: Int64, readBytesPerSecond: Double = 450e6, memoryBandwidthBytesPerSecond: Double = 307e9) {
        self.memoryBudgetBytes = memoryBudgetBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.memoryBandwidthBytesPerSecond = memoryBandwidthBytesPerSecond
    }
}

public struct RouteRequest: Sendable {
    public var profile: TaskProfile
    public var mode: RouterMode
    public var preference: RouterPreference
    public var manualModelID: String?
    /// Modell, das im Chat zuletzt geantwortet hat
    public var currentModelID: String?
    /// erweiterte Option: im manuellen Modus Wechsel vorschlagen (nie selbst ausführen)
    public var allowSwitchInManual: Bool

    public init(
        profile: TaskProfile, mode: RouterMode, preference: RouterPreference = .balanced,
        manualModelID: String? = nil, currentModelID: String? = nil, allowSwitchInManual: Bool = false
    ) {
        self.profile = profile
        self.mode = mode
        self.preference = preference
        self.manualModelID = manualModelID
        self.currentModelID = currentModelID
        self.allowSwitchInManual = allowSwitchInManual
    }
}

public struct ScoredCandidate: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var score: Double
    public var quality: Double
    public var tempo: Double
    public var estimatedTokensPerSecond: Double
    public var loadSeconds: Double
    public var memoryShare: Double
    public var excludedReason: String?
}

public struct RouteDecision: Sendable {
    public var modelID: String?
    public var modelName: String?
    /// Ein Satz Begründung, wird im Chat angezeigt
    public var reason: String
    public var isSwitch: Bool
    public var previousModelID: String?
    /// Hinweis ohne Eingriff, z. B. im manuellen Modus
    public var warning: String?
    /// Vorschlag für einen Wechsel (nur im manuellen Modus mit erlaubter Option)
    public var suggestedModelID: String?
    public var candidates: [ScoredCandidate]
}

/// Der AUTO-Router: hart filtern, bewerten, nur bei echtem Gewinn wechseln.
/// Im manuellen Modus wird die Wahl des Nutzers nie ersetzt.
public enum Router {
    /// Ein Wechsel muss die Bewertung um mindestens 15 % verbessern
    public static let switchGain = 0.15
    /// Reserve für KV-Cache und Laufzeit neben den Gewichten
    public static let kvReserveBytes: Int64 = 2_000_000_000

    public static func fits(bytes: Int64, budget: Int64) -> Bool {
        Double(bytes) * 1.1 + Double(kvReserveBytes) <= Double(budget)
    }

    static func exclusion(_ c: RouterCandidate, profile: TaskProfile, context: RouterContext) -> String? {
        if !c.isAvailable { return "ist nicht verfügbar (Laufwerk nicht verbunden)" }
        if c.descriptor.license.blockedInEU { return "ist laut Lizenz in der EU nicht nutzbar" }
        let missing = profile.required.subtracting(c.descriptor.capabilities)
        if missing.contains(.vision) { return "kann keine Bilder lesen" }
        if missing.contains(.longContext) { return "hat ein zu kurzes Kontextfenster" }
        if let other = missing.first { return "kann keine Aufgabe der Art „\(other.title)“" }
        if profile.estimatedTokens > Int(Double(c.descriptor.contextTokens) * 0.9) {
            return "hat ein zu kurzes Kontextfenster (\(Format.contextTokens(c.descriptor.contextTokens)))"
        }
        if !fits(bytes: c.bytes, budget: context.memoryBudgetBytes) {
            return "passt gerade nicht in den freien Speicher"
        }
        return nil
    }

    public static func estimatedTokensPerSecond(_ c: RouterCandidate, context: RouterContext) -> Double {
        if let measured = c.measuredTokensPerSecond, measured > 0 { return measured }
        let total = max(c.descriptor.totalParamsB, 0.1) * 1e9
        let bytesPerParam = Double(c.bytes) / total
        let activeBytes = max(c.descriptor.activeParamsB * 1e9 * bytesPerParam, 1e8)
        // Obergrenze: Bandbreite / aktive Bytes je Token; in der Praxis etwa 60 % davon
        return min(160, 0.6 * context.memoryBandwidthBytesPerSecond / activeBytes)
    }

    public static func score(
        _ c: RouterCandidate, profile: TaskProfile, preference: RouterPreference, context: RouterContext
    ) -> ScoredCandidate {
        let q = c.measuredQuality[profile.kind] ?? c.descriptor.quality(for: profile.kind)
        let tps = estimatedTokensPerSecond(c, context: context)
        let t = min(1, tps / 80)
        let loadSeconds = c.isLoaded ? 0 : Double(c.bytes) / max(context.readBytesPerSecond, 50e6)
        let l = min(1, loadSeconds / 90)
        let s = min(1, Double(c.bytes) / Double(max(context.memoryBudgetBytes, 1)))
        let w = preference.weights
        var value = w.quality * q + w.tempo * t - w.load * l - w.memory * s
        if profile.kind == .quick { value += 0.10 * t }
        if profile.difficulty >= 4 { value += 0.10 * q }
        return ScoredCandidate(
            id: c.descriptor.id, name: c.descriptor.name, score: value, quality: q, tempo: t,
            estimatedTokensPerSecond: tps, loadSeconds: loadSeconds, memoryShare: s,
            excludedReason: exclusion(c, profile: profile, context: context))
    }

    static func improvement(_ new: Double, over old: Double) -> Double {
        (new - old) / max(abs(old), 0.05)
    }

    public static func decide(_ request: RouteRequest, candidates: [RouterCandidate], context: RouterContext) -> RouteDecision {
        let profile = request.profile
        let scored = candidates.map { score($0, profile: profile, preference: request.preference, context: context) }
            .sorted { $0.score > $1.score }
        let current = request.currentModelID

        // MANUELL: Die Wahl des Nutzers gilt – der Router gibt nur Hinweise.
        if request.mode == .manual {
            guard let manualID = request.manualModelID,
                  let manual = candidates.first(where: { $0.descriptor.id == manualID }) else {
                return RouteDecision(
                    modelID: nil, modelName: nil,
                    reason: "Im manuellen Modus ist noch kein Modell gewählt.",
                    isSwitch: false, previousModelID: current, warning: nil, suggestedModelID: nil, candidates: scored)
            }
            if !manual.isAvailable {
                return RouteDecision(
                    modelID: nil, modelName: manual.descriptor.name,
                    reason: "\(manual.descriptor.name) ist nicht verfügbar. Ist das Laufwerk mit den Modellen verbunden?",
                    isSwitch: false, previousModelID: current, warning: nil, suggestedModelID: nil, candidates: scored)
            }
            let problem = exclusion(manual, profile: profile, context: context)
            var suggestion: String?
            if problem != nil, request.allowSwitchInManual {
                suggestion = scored.first(where: { $0.excludedReason == nil && $0.id != manualID })?.id
            }
            return RouteDecision(
                modelID: manualID, modelName: manual.descriptor.name,
                reason: "Manuell gewählt",
                isSwitch: current != nil && current != manualID, previousModelID: current,
                warning: problem.map { "Hinweis: \(manual.descriptor.name) \($0)." },
                suggestedModelID: suggestion, candidates: scored)
        }

        // AUTO
        let eligible = scored.filter { $0.excludedReason == nil }
        guard let best = eligible.first else {
            let reason: String
            if candidates.isEmpty {
                reason = "Noch kein Modell installiert. Lade im Bereich „Modelle“ ein Modell herunter."
            } else if let first = scored.first, let why = first.excludedReason {
                reason = "Kein installiertes Modell passt zu dieser Aufgabe – zum Beispiel \(first.name) \(why)."
            } else {
                reason = "Kein installiertes Modell passt zu dieser Aufgabe."
            }
            return RouteDecision(
                modelID: nil, modelName: nil, reason: reason, isSwitch: false, previousModelID: current,
                warning: nil, suggestedModelID: nil, candidates: scored)
        }

        if let currentID = current, let cur = scored.first(where: { $0.id == currentID }) {
            if cur.excludedReason == nil {
                if best.id == cur.id || improvement(best.score, over: cur.score) < switchGain {
                    return RouteDecision(
                        modelID: cur.id, modelName: cur.name, reason: "\(cur.name) bleibt aktiv · \(profile.kind.title)",
                        isSwitch: false, previousModelID: currentID, warning: nil, suggestedModelID: nil, candidates: scored)
                }
                let gain = Int((improvement(best.score, over: cur.score) * 100).rounded())
                return RouteDecision(
                    modelID: best.id, modelName: best.name,
                    reason: "\(profile.kind.title): \(best.name) ist hier \(gain) % besser bewertet",
                    isSwitch: true, previousModelID: currentID, warning: nil, suggestedModelID: nil, candidates: scored)
            }
            return RouteDecision(
                modelID: best.id, modelName: best.name,
                reason: "\(cur.name) \(cur.excludedReason ?? "passt nicht") – \(best.name) übernimmt",
                isSwitch: true, previousModelID: currentID, warning: nil, suggestedModelID: nil, candidates: scored)
        }

        return RouteDecision(
            modelID: best.id, modelName: best.name, reason: describe(best, among: eligible, profile: profile, candidates: candidates),
            isSwitch: false, previousModelID: current, warning: nil, suggestedModelID: nil, candidates: scored)
    }

    static func describe(_ best: ScoredCandidate, among eligible: [ScoredCandidate], profile: TaskProfile, candidates: [RouterCandidate]) -> String {
        let loaded = candidates.first(where: { $0.descriptor.id == best.id })?.isLoaded == true
        var parts = [profile.kind.title]
        parts.append(loaded ? "schon geladen" : "wird geladen")
        if eligible.count > 1 {
            if best.quality >= (eligible.map(\.quality).max() ?? 0) {
                parts.append("beste Qualität für diese Aufgabe")
            } else if best.tempo >= (eligible.map(\.tempo).max() ?? 0) {
                parts.append("am schnellsten")
            } else {
                parts.append("bestes Verhältnis aus Qualität und Tempo")
            }
        }
        return "\(best.name) – " + parts.joined(separator: ", ")
    }
}
