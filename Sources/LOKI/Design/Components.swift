import SwiftUI

/// Kleine Kapsel für Eigenschaften wie Lizenz, Offenheit oder Fähigkeiten
struct Badge: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = .secondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.lokiCaption).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(filled ? Color.white : tint)
        .background(
            Capsule().fill(filled ? tint : tint.opacity(0.13)))
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

/// Fortschritt mit Verlauf Blau → Cyan
struct LokiProgressBar: View {
    var value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Loki.well)
                Capsule()
                    .fill(LinearGradient(colors: [Loki.accent, Loki.progressEnd], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .shadow(color: Loki.accent.opacity(0.35), radius: 4)
            }
        }
        .frame(height: height)
        .animation(Loki.state, value: value)
    }
}

/// Belegung, z. B. Arbeitsspeicher oder Laufwerk
struct MeterBar: View {
    var fraction: Double
    var height: CGFloat = 6

    var color: Color {
        if fraction > 0.9 { return Loki.danger }
        if fraction > 0.75 { return Loki.warning }
        return Loki.accent
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Loki.well)
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .animation(Loki.state, value: fraction)
    }
}

struct SectionHeader: View {
    var title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.lokiTitle2)
            if let detail { Text(detail).font(.lokiCallout).foregroundStyle(.secondary) }
            Spacer()
        }
    }
}

/// Hebt Karten beim Überfahren leicht an und gibt beim Drücken nach
struct HoverLift: ViewModifier {
    @State private var hovering = false
    var lift: CGFloat = 2.5

    func body(content: Content) -> some View {
        content
            .offset(y: hovering ? -lift : 0)
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: hovering ? 18 : 0, y: hovering ? 10 : 0)
            .animation(Loki.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(_ lift: CGFloat = 2.5) -> some View { modifier(HoverLift(lift: lift)) }
}

/// Knopfstil für Flächen, die beim Drücken auf 97 % nachgeben
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Loki.spring, value: configuration.isPressed)
    }
}

/// Symbol in einer getönten Glasfläche (Kategorien: Stahlblau, Salbei, Sand)
struct IconTile: View {
    var systemImage: String
    var tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(tint.opacity(0.14)))
    }
}

/// Hinweis „Demo-Daten“ – nur im Vorschau-/Prüfmodus sichtbar
struct DemoBadge: View {
    var body: some View {
        Badge(text: "Demo-Daten (Prüfmodus)", systemImage: "eye", tint: Loki.warning)
    }
}
