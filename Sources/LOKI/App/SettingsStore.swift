import Foundation
import SwiftUI
import LokiCore

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Wie System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Einstellungen, gespeichert in den Benutzereinstellungen (im Prüfmodus in einer eigenen Domäne).
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var modelRootPath: String? { didSet { defaults.set(modelRootPath, forKey: "modelRootPath") } }
    @Published var preference: RouterPreference { didSet { defaults.set(preference.rawValue, forKey: "preference") } }
    @Published var defaultMode: RouterMode { didSet { defaults.set(defaultMode.rawValue, forKey: "defaultMode") } }
    @Published var allowSwitchInManual: Bool { didSet { defaults.set(allowSwitchInManual, forKey: "allowSwitchInManual") } }
    @Published var maxLoadedModels: Int { didSet { defaults.set(maxLoadedModels, forKey: "maxLoadedModels") } }
    @Published var appearance: AppearanceChoice { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var thinkingVisible: Bool { didSet { defaults.set(thinkingVisible, forKey: "thinkingVisible") } }
    /// gemessene Werte je Modell: Token/s
    @Published var measuredSpeed: [String: Double] { didSet { defaults.set(measuredSpeed, forKey: "measuredSpeed") } }
    /// gemessene Lesegeschwindigkeit je Laufwerk (Volume-UUID → Byte/s)
    @Published var driveReadSpeed: [String: Double] { didSet { defaults.set(driveReadSpeed, forKey: "driveReadSpeed") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modelRootPath = defaults.string(forKey: "modelRootPath")
        preference = RouterPreference(rawValue: defaults.string(forKey: "preference") ?? "") ?? .balanced
        defaultMode = RouterMode(rawValue: defaults.string(forKey: "defaultMode") ?? "") ?? .auto
        allowSwitchInManual = defaults.bool(forKey: "allowSwitchInManual")
        let maxLoaded = defaults.integer(forKey: "maxLoadedModels")
        maxLoadedModels = maxLoaded == 0 ? 1 : maxLoaded
        appearance = AppearanceChoice(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        thinkingVisible = defaults.object(forKey: "thinkingVisible") as? Bool ?? false
        measuredSpeed = defaults.dictionary(forKey: "measuredSpeed") as? [String: Double] ?? [:]
        driveReadSpeed = defaults.dictionary(forKey: "driveReadSpeed") as? [String: Double] ?? [:]
    }

    var modelRoot: URL? { modelRootPath.map { URL(fileURLWithPath: $0, isDirectory: true) } }
}
