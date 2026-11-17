import SwiftUI
import AppKit

// LOKI-Designsystem: klares Liquid Glass, neutrale Graphit- und Weißtöne, Blau als einziger Akzent.

extension Color {
    /// Farbe mit eigenen Werten für Hell und Dunkel (keine invertierten Farben)
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(opacity))
        })
    }
}

extension Color {
    /// Weiß- bzw. Graphitschleier mit eigener Deckkraft je Modus
    init(lightOpacity: Double, darkOpacity: Double, light: UInt32 = 0xFFFFFF, dark: UInt32 = 0xFFFFFF) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(isDark ? darkOpacity : lightOpacity))
        })
    }
}

enum Loki {
    /// leichte Fläche für Nachrichten und Listenzeilen (günstiger als echtes Glas in langen Listen)
    static let surface = Color(lightOpacity: 0.62, darkOpacity: 0.05)
    static let surfaceHover = Color(lightOpacity: 0.85, darkOpacity: 0.08)
    static let userBubble = Color(lightOpacity: 0.14, darkOpacity: 0.20, light: 0x007AFF, dark: 0x0A84FF)

    // Farben
    static let accent = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let accentText = Color(light: 0x0066CC, dark: 0x4DA3FF)
    static let progressEnd = Color(light: 0x5AC8FA, dark: 0x64D2FF)
    static let backgroundTop = Color(light: 0xF5F7FA, dark: 0x12151B)
    static let backgroundBottom = Color(light: 0xE9EDF2, dark: 0x0B0D11)
    static let steel = Color(light: 0x5B7A99, dark: 0x8FA9C4)
    static let sage = Color(light: 0x5E8C6A, dark: 0x93BFA0)
    static let sand = Color(light: 0x9C8058, dark: 0xD2B78E)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF, opacity: 0.08)
    static let well = Color(light: 0x1C2430, dark: 0xFFFFFF, opacity: 0.05)

    // Radien
    enum Radius {
        static let small: CGFloat = 10
        static let field: CGFloat = 14
        static let image: CGFloat = 16
        static let card: CGFloat = 22
        static let composer: CGFloat = 28
        static let dock: CGFloat = 32
    }

    // Abstände im 4/8-Raster
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // Bewegung: Feder mit 0,35 s Ansprechzeit und Dämpfung 0,86
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let hover = Animation.easeOut(duration: 0.18)
    static let state = Animation.easeInOut(duration: 0.28)
    static let lens = Animation.spring(response: 0.44, dampingFraction: 0.86)
}

// Typografie (SF Pro, ab 20 pt als Display)
extension Font {
    static let lokiLargeTitle = Font.system(size: 40, weight: .bold)
    static let lokiTitle = Font.system(size: 30, weight: .bold)
    static let lokiTitle2 = Font.system(size: 20, weight: .bold)
    static let lokiHeadline = Font.system(size: 15.5, weight: .semibold)
    static let lokiBody = Font.system(size: 15)
    static let lokiCallout = Font.system(size: 13, weight: .semibold)
    static let lokiCaption = Font.system(size: 11.5, weight: .semibold)
    static let lokiMono = Font.system(size: 12.5, design: .monospaced)
}

/// Hintergrund: Graphit (dunkel) bzw. kühles Weiß (hell) mit Licht von oben
struct LokiBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Loki.backgroundTop, Loki.backgroundBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Color.white.opacity(scheme == .dark ? 0.06 : 0.55), .clear],
                center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 760)
            RadialGradient(
                colors: [Loki.accent.opacity(scheme == .dark ? 0.10 : 0.07), .clear],
                center: UnitPoint(x: 0.85, y: 0.05), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glasflächen

extension View {
    /// Grundglas für Karten und Listen
    func lokiCard(radius: CGFloat = Loki.Radius.card, padding: CGFloat = Loki.Space.l) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Mulde für Felder und Codeblöcke
    func lokiWell(radius: CGFloat = Loki.Radius.field) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Loki.well)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Loki.hairline, lineWidth: 1)))
    }

    /// Fokusring: weicher Akzentring um das Glas
    func lokiFocusRing(_ active: Bool, radius: CGFloat) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Loki.accent.opacity(active ? 0.55 : 0), lineWidth: 2)
                .shadow(color: Loki.accent.opacity(active ? 0.35 : 0), radius: 6)
                .allowsHitTesting(false))
    }
}
