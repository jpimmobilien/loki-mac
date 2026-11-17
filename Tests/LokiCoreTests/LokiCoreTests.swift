import XCTest
@testable import LokiCore

final class RouterTests: XCTestCase {
    let context = RouterContext(memoryBudgetBytes: 44_000_000_000, readBytesPerSecond: 450e6)

    func candidate(_ id: String, loaded: Bool = false, available: Bool = true) -> RouterCandidate {
        RouterCandidate(descriptor: Catalog.descriptor(for: id)!, isAvailable: available, isLoaded: loaded)
    }

    func testManualChoiceIsNeverOverridden() {
        let small = candidate("mlx-community/Qwen3-4B-4bit")
        let big = candidate("mlx-community/Qwen3.6-27B-4bit", loaded: true)
        let profile = TaskClassifier.classify("Analysiere bitte Schritt für Schritt die Vor- und Nachteile dieser Strategie.")
        let request = RouteRequest(profile: profile, mode: .manual, manualModelID: small.descriptor.id, currentModelID: small.descriptor.id)
        let decision = Router.decide(request, candidates: [small, big], context: context)
        XCTAssertEqual(decision.modelID, small.descriptor.id)
        XCTAssertFalse(decision.isSwitch)
        XCTAssertNil(decision.suggestedModelID)
    }

    func testManualModeGivesHintButKeepsModel() {
        let small = candidate("mlx-community/Qwen3-4B-4bit")
        let gemma = candidate("mlx-community/gemma-4-26b-a4b-it-4bit")
        let profile = TaskClassifier.classify("Was ist auf dem Bild?", hasImage: true)
        let request = RouteRequest(profile: profile, mode: .manual, manualModelID: small.descriptor.id, allowSwitchInManual: true)
        let decision = Router.decide(request, candidates: [small, gemma], context: context)
        XCTAssertEqual(decision.modelID, small.descriptor.id, "Manuell gewähltes Modell bleibt")
        XCTAssertNotNil(decision.warning)
    }

    func testAutoExcludesModelsWithoutRequiredCapability() {
        let small = candidate("mlx-community/Qwen3-4B-4bit")
        let profile = TaskClassifier.classify("Beschreibe das Bild", hasImage: true)
        let decision = Router.decide(RouteRequest(profile: profile, mode: .auto), candidates: [small], context: context)
        XCTAssertNil(decision.modelID)
        XCTAssertTrue(decision.reason.contains("Bilder"))
    }

    func testAutoKeepsCurrentModelWithoutClearGain() {
        let a = candidate("mlx-community/Qwen3-8B-4bit", loaded: true)
        let b = candidate("mlx-community/GLM-4-9B-0414-4bit")
        let profile = TaskClassifier.classify("Wie spät ist es in Tokio, wenn es in Berlin 12 Uhr ist?")
        let decision = Router.decide(
            RouteRequest(profile: profile, mode: .auto, currentModelID: a.descriptor.id), candidates: [a, b], context: context)
        XCTAssertEqual(decision.modelID, a.descriptor.id)
        XCTAssertFalse(decision.isSwitch)
    }

    func testAutoSwitchesWhenClearlyBetter() {
        let small = candidate("mlx-community/Llama-3.2-3B-Instruct-4bit", loaded: true)
        let coder = candidate("mlx-community/Qwen3.6-27B-4bit", loaded: true)
        let profile = TaskClassifier.classify("""
        Hier ist mein Swift-Code, der nicht kompiliert. Bitte finde den Fehler:
        ```swift
        struct A { let x: Int }
        func f() { let a = A(); print(a.x) }
        ```
        """)
        XCTAssertEqual(profile.kind, .coding)
        let decision = Router.decide(
            RouteRequest(profile: profile, mode: .auto, currentModelID: small.descriptor.id),
            candidates: [small, coder], context: context)
        XCTAssertEqual(decision.modelID, coder.descriptor.id)
        XCTAssertTrue(decision.isSwitch)
    }

    func testMemoryFilter() {
        let huge = candidate("mlx-community/Qwen3-Coder-Next-4bit")
        let tight = RouterContext(memoryBudgetBytes: 20_000_000_000)
        let profile = TaskClassifier.classify("Schreibe eine Funktion in Swift, die eine Liste sortiert und den Code erklärt.")
        let decision = Router.decide(RouteRequest(profile: profile, mode: .auto), candidates: [huge], context: tight)
        XCTAssertNil(decision.modelID)
        XCTAssertTrue(decision.reason.contains("Speicher"))
    }

    func testUnavailableDriveIsExcluded() {
        let offline = candidate("mlx-community/Qwen3-8B-4bit", available: false)
        let online = candidate("mlx-community/Qwen3-4B-4bit")
        let profile = TaskClassifier.classify("Hallo, wie geht es dir?")
        let decision = Router.decide(RouteRequest(profile: profile, mode: .auto), candidates: [offline, online], context: context)
        XCTAssertEqual(decision.modelID, online.descriptor.id)
    }

    func testEUBlockedLicenseIsExcluded() {
        var blocked = Catalog.descriptor(for: "mlx-community/Qwen3-8B-4bit")!
        blocked.id = "test/blocked"
        blocked.license = LicenseInfo(name: "Test", licenseClass: .conditions, blockedInEU: true)
        let decision = Router.decide(
            RouteRequest(profile: TaskClassifier.classify("Hallo"), mode: .auto),
            candidates: [RouterCandidate(descriptor: blocked)], context: context)
        XCTAssertNil(decision.modelID)
    }
}

final class ClassifierTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(TaskClassifier.classify("Hallo!").kind, .quick)
        XCTAssertEqual(TaskClassifier.classify("Schreibe eine freundliche E-Mail an einen Mieter wegen der Nebenkostenabrechnung.").kind, .writing)
        XCTAssertEqual(TaskClassifier.classify("Vergleiche die Vor- und Nachteile von Miete und Kauf und begründe deine Empfehlung.").kind, .reasoning)
        XCTAssertEqual(TaskClassifier.classify("Mein Kotlin-Code in Android Studio wirft eine Exception beim Start.").kind, .coding)
        XCTAssertEqual(TaskClassifier.classify("Was ist das?", hasImage: true).required, [.vision])
        let long = String(repeating: "Ein sehr langer Vertragstext. ", count: 4000)
        XCTAssertEqual(TaskClassifier.classify(long).kind, .longContext)
    }
}

final class ContextEngineTests: XCTestCase {
    func testKeepsRecentTurnsAndSummarizesOlder() {
        var history: [ContextTurn] = []
        for i in 0..<40 {
            history.append(ContextTurn(role: .user, text: "Frage \(i): " + String(repeating: "x", count: 600)))
            history.append(ContextTurn(role: .assistant, text: "Antwort \(i): " + String(repeating: "y", count: 600), modelName: "Qwen3 4B"))
        }
        let pack = ContextEngine.build(history: history, budgetTokens: 4000)
        XCTAssertLessThanOrEqual(pack.estimatedTokens, 4000)
        XCTAssertGreaterThan(pack.summarizedCount, 0)
        XCTAssertEqual(pack.turns.first?.role, .user)
        XCTAssertEqual(pack.turns.last?.text, history.last?.text)
        XCTAssertTrue(pack.instructions.contains("Zusammenfassung"))
    }

    func testShortHistoryStaysVerbatim() {
        let history = [
            ContextTurn(role: .user, text: "Hallo"),
            ContextTurn(role: .assistant, text: "Hallo! Wie kann ich helfen?"),
        ]
        let pack = ContextEngine.build(history: history, budgetTokens: 4000)
        XCTAssertEqual(pack.turns, history)
        XCTAssertEqual(pack.summarizedCount, 0)
    }

    func testBudgetFromWindow() {
        XCTAssertEqual(ContextEngine.budget(forContextWindow: 32_768), 19_660)
        XCTAssertEqual(ContextEngine.budget(forContextWindow: 262_144), 32_768)
    }
}

final class FormatTests: XCTestCase {
    func testFormats() {
        XCTAssertEqual(Format.bytes(Int64(2_300_000_000)), "2,3 GB")
        XCTAssertEqual(Format.params(3.8), "3,8B")
        XCTAssertEqual(Format.contextTokens(262_144), "256K")
    }
}
