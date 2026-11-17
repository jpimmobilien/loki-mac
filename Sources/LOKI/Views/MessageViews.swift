import SwiftUI
import AppKit
import LokiCore

struct MessageRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: ModelLibrary
    var message: ChatMessage
    var conversationID: UUID

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistantCard
        case .notice: notice
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 120)
            Text(message.text)
                .font(.lokiBody)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Loki.userBubble))
        }
    }

    @State private var showReason = false
    @State private var showThinking: Bool? = nil

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Badge(text: message.modelName ?? "Modell", systemImage: "cpu", tint: Loki.accentText)
                Badge(text: "lokal", systemImage: "lock.fill", tint: Loki.sage)
                if let stats = message.stats {
                    Text("\(Format.tokensPerSecond(stats.tokensPerSecond)) · erstes Wort nach \(Format.seconds(stats.timeToFirstToken))")
                        .font(.lokiCaption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if let reason = message.routeReason {
                    Button { showReason.toggle() } label: {
                        Image(systemName: "info.circle").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Warum dieses Modell?")
                    .popover(isPresented: $showReason, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Warum dieses Modell?").font(.lokiHeadline)
                            Text(reason).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(width: 320)
                    }
                }
            }

            if let reasoning = message.reasoning, !reasoning.isEmpty {
                DisclosureGroup(isExpanded: Binding(
                    get: { showThinking ?? (settings.thinkingVisible || (message.isStreaming && message.text.isEmpty)) },
                    set: { showThinking = $0 })
                ) {
                    Text(reasoning)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Label(message.isStreaming && message.text.isEmpty ? "Denkt nach …" : "Gedankengang", systemImage: "brain")
                        .font(.lokiCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if message.text.isEmpty && message.isStreaming && (message.reasoning ?? "").isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Liest den Kontext ein …").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            } else if !message.text.isEmpty {
                MarkdownText(text: message.text)
            }

            if message.wasCancelled {
                Label("Abgebrochen", systemImage: "stop.circle").font(.lokiCaption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Loki.Radius.card, style: .continuous)
                .fill(Loki.surface)
                .overlay(RoundedRectangle(cornerRadius: Loki.Radius.card, style: .continuous).strokeBorder(Loki.hairline, lineWidth: 1)))
    }

    private var notice: some View {
        let kind = message.noticeKind ?? .info
        let tint: Color = {
            switch kind {
            case .modelSwitch: return Loki.accentText
            case .info: return .secondary
            case .warning: return Loki.warning
            case .error: return Loki.danger
            }
        }()
        let icon: String = {
            switch kind {
            case .modelSwitch: return "arrow.triangle.swap"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }()
        return HStack {
            Spacer(minLength: 40)
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(message.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(kind == .info ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggested = message.suggestedModelID {
                    Button("Zu \(library.installedModel(suggested)?.descriptor.name ?? suggested) wechseln") {
                        model.applySuggestion(suggested, in: conversationID)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.10)))
            Spacer(minLength: 40)
        }
    }
}

/// Einfache Markdown-Darstellung: Fließtext mit Inline-Formatierung, Überschriften fett, Codeblöcke in einer Mulde.
struct MarkdownText: View {
    var text: String

    private struct Segment: Identifiable {
        var id: Int
        var isCode: Bool
        var language: String?
        var content: String
    }

    private var segments: [Segment] {
        let parts = text.components(separatedBy: "```")
        return parts.enumerated().compactMap { index, part in
            if index % 2 == 1 {
                var lines = part.components(separatedBy: "\n")
                let first = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
                let language = first.isEmpty || first.contains(" ") ? nil : first
                if language != nil || first.isEmpty { lines.removeFirst() }
                let code = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
                return Segment(id: index, isCode: true, language: language, content: code)
            }
            let trimmed = part.trimmingCharacters(in: .newlines)
            return trimmed.isEmpty ? nil : Segment(id: index, isCode: false, language: nil, content: trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                if segment.isCode {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(segment.language ?? "Code").font(.lokiCaption).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(segment.content, forType: .string)
                            } label: {
                                Label("Kopieren", systemImage: "doc.on.doc").font(.lokiCaption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(segment.content)
                                .font(.lokiMono)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(12)
                    .lokiWell(radius: 12)
                } else {
                    Text(Self.attributed(segment.content))
                        .font(.lokiBody)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    static func attributed(_ markdown: String) -> AttributedString {
        // Überschriften („# Titel“) als fetten Text darstellen
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? line : "**\(title)**"
            }
            if trimmed.hasPrefix("* ") { return "• " + trimmed.dropFirst(2) }
            if trimmed.hasPrefix("- ") { return "• " + trimmed.dropFirst(2) }
            return line
        }
        let prepared = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(prepared)
    }
}
