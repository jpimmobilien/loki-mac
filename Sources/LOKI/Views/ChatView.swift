import SwiftUI
import AppKit
import LokiCore

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ConversationList()
                .frame(width: 260)
            VStack(spacing: 12) {
                header
                if let conv = model.selectedConversation, !conv.messages.isEmpty {
                    MessageList(conversation: conv)
                } else {
                    emptyState
                }
                Composer(style: .chat)
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 108)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.selectedConversation?.title ?? "Neuer Chat")
                .font(.lokiTitle)
                .lineLimit(1)
            if model.isQAMode { DemoBadge() }
            Spacer()
            Badge(
                text: model.currentMode == .auto ? "AUTO MODE" : "Manuell",
                systemImage: model.currentMode == .auto ? "wand.and.stars" : "hand.point.up.left",
                tint: model.currentMode == .auto ? Loki.accentText : Loki.steel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Loki.accentText)
            Text("Neuer Chat").font(.lokiTitle2)
            VStack(alignment: .leading, spacing: 8) {
                Label("**Auto:** LOKI wählt für jede Anfrage das passende lokale Modell und darf mitten im Chat wechseln. Jeder Wechsel wird mit Grund angezeigt.", systemImage: "wand.and.stars")
                Label("**Manuell:** Dein gewähltes Modell beantwortet den ganzen Chat. LOKI ersetzt es nie heimlich.", systemImage: "hand.point.up.left")
                Label("Alles bleibt auf deinem Mac. Ohne Internet funktioniert der Chat genauso.", systemImage: "lock.shield")
            }
            .font(.system(size: 13.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 560, alignment: .leading)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MessageList: View {
    @EnvironmentObject private var model: AppModel
    var conversation: Conversation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(conversation.messages) { message in
                        MessageRow(message: message, conversationID: conversation.id)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 4).id("ende")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.automatic)
            .onAppear { proxy.scrollTo("ende", anchor: .bottom) }
            .onChange(of: conversation.messages.last?.text) {
                proxy.scrollTo("ende", anchor: .bottom)
            }
            .onChange(of: conversation.messages.count) {
                withAnimation(Loki.state) { proxy.scrollTo("ende", anchor: .bottom) }
            }
        }
    }
}

struct ConversationList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.newConversation()
            } label: {
                Label("Neuer Chat", systemImage: "square.and.pencil")
                    .font(.lokiCallout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.conversations) { conv in
                        row(conv)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Loki.Radius.card, style: .continuous))
    }

    private func row(_ conv: Conversation) -> some View {
        let selected = conv.id == model.selectedConversationID
        return Button { model.select(conv.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: conv.mode == .auto ? "wand.and.stars" : "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Loki.accentText : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(conv.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                    Text(conv.updated, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Loki.accent.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Löschen", role: .destructive) { model.delete(conv.id) }
        }
    }
}
