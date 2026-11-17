import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ZStack(alignment: .bottom) {
            LokiBackground()
            VStack(spacing: 0) {
                TopBar()
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            ActivityDock()
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            if let toast = model.toast {
                ToastView(text: toast) { model.toast = nil }
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Loki.state, value: model.tab)
        .animation(Loki.spring, value: model.toast)
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .home: HomeView()
        case .chat: ChatView()
        case .models: ModelsView()
        case .settings: SettingsView()
        case .history: HistoryView()
        default: PlannedView(tab: model.tab)
        }
    }
}

struct ToastView: View {
    var text: String
    var close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Loki.accentText)
            Text(text).font(.lokiCallout).lineLimit(3)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: Capsule())
        .task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            close()
        }
    }
}

/// Schwebende Glas-Navigation mit gleitender Linse
struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var lens

    var body: some View {
        HStack(spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 2) {
                        ForEach(AppTab.primary) { tabButton($0) }
                        Rectangle()
                            .fill(Loki.hairline)
                            .frame(width: 1, height: 28)
                            .padding(.horizontal, 6)
                        ForEach(AppTab.secondary) { tabButton($0) }
                    }
                    .padding(5)
                    .glassEffect(.regular, in: Capsule())

                    Button {
                        withAnimation(Loki.lens) { model.tab = .settings }
                    } label: {
                        Image(systemName: AppTab.settings.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(model.tab == .settings ? Loki.accentText : .primary)
                            .frame(width: 46, height: 46)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                    .glassEffect(model.tab == .settings ? .regular.tint(Loki.accent.opacity(0.25)) : .regular, in: Circle())
                    .help("Einstellungen")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 84) // Platz für die Fensterknöpfe
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let active = model.tab == tab
        return Button {
            withAnimation(Loki.lens) { model.tab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                Text(tab.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(active ? Loki.accentText : (tab.isAvailable ? Color.primary : Color.secondary))
            .frame(width: 82, height: 42)
            .background {
                if active {
                    Capsule()
                        .fill(Loki.accent.opacity(0.16))
                        .overlay(Capsule().strokeBorder(Loki.accent.opacity(0.28), lineWidth: 1))
                        .matchedGeometryEffect(id: "lens", in: lens)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .help(tab.isAvailable ? tab.title : "\(tab.title) – geplant")
    }
}
