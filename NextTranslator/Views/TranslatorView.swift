import SwiftUI

extension TranslatorAction {
    /// Verb shown on the action button ("Translate", "Polish", …).
    var actionVerb: String {
        switch builtinMode {
        case "translate": return String(localized: "Translate")
        case "polishing": return String(localized: "Polish")
        case "summarize": return String(localized: "Summarize")
        case "analyze": return String(localized: "Analyze")
        case "explain-code": return String(localized: "Explain")
        default: return name
        }
    }

    /// Progressive form shown while streaming ("Translating…", …).
    var progressiveVerb: String {
        switch builtinMode {
        case "translate": return String(localized: "Translating…")
        case "polishing": return String(localized: "Polishing…")
        case "summarize": return String(localized: "Summarizing…")
        case "analyze": return String(localized: "Analyzing…")
        case "explain-code": return String(localized: "Explaining…")
        default: return name + "…"
        }
    }
}

struct TranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var actionStore = ActionStore.shared
    @State private var draft: String = ""
    @State private var showHistory = false
    @State private var fullPillsWidth: CGFloat = 0
    @State private var iconPillsWidth: CGFloat = 0
    @Namespace private var glassNamespace

    var body: some View {
        VStack(spacing: 12) {
            headerBar
            editorCard
            resultCard
            footerBar
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 560)
        .containerBackground(.thinMaterial, for: .window)
        .onChange(of: appState.querySeq) {
            draft = appState.inputText
        }
        .onAppear {
            draft = appState.inputText
        }
    }

    // MARK: header — justified action pills, brand and pin at the trailing edge

    private var headerBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                actionsArea
                HStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Next Translator")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                pinButton
            }
        }
    }

    /// Justified pill row that degrades gracefully: full labels spread across
    /// the available width, icon-only pills when labels no longer fit, and a
    /// horizontal scroller as the last resort.
    private var actionsArea: some View {
        GeometryReader { geo in
            Group {
                if fullPillsWidth <= geo.size.width {
                    justifiedPills(iconOnly: false)
                } else if iconPillsWidth <= geo.size.width {
                    justifiedPills(iconOnly: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(actionStore.actions) { action in
                                actionPill(action, iconOnly: true)
                            }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(measurementProbe)
    }

    /// Invisible fixed-size copies of both pill rows report their natural
    /// widths so the visible row can pick the widest variant that fits.
    private var measurementProbe: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(actionStore.actions) { action in
                    actionPill(action, iconOnly: false)
                }
            }
            .fixedSize()
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { fullPillsWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in fullPillsWidth = w }
                }
            )
            HStack(spacing: 6) {
                ForEach(actionStore.actions) { action in
                    actionPill(action, iconOnly: true)
                }
            }
            .fixedSize()
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { iconPillsWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in iconPillsWidth = w }
                }
            )
        }
        .hidden()
        .allowsHitTesting(false)
    }

    private func justifiedPills(iconOnly: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(actionStore.actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Spacer(minLength: 6)
                }
                actionPill(action, iconOnly: iconOnly)
            }
        }
    }

    private func actionPill(_ action: TranslatorAction, iconOnly: Bool) -> some View {
        let selected = appState.currentAction.id == action.id
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                appState.currentAction = action
            }
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translateDraft()
            }
        } label: {
            Group {
                if iconOnly {
                    Image(systemName: action.icon)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                } else {
                    Label(action.name, systemImage: action.icon)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, iconOnly ? 9 : 12)
            .padding(.vertical, 7)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .glassEffectID(action.id, in: glassNamespace)
        .help(action.name)
    }

    private var pinButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                appState.toggleAlwaysOnTop()
            }
        } label: {
            Image(systemName: appState.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(appState.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(8)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(
            appState.isPinned ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: .circle
        )
        .help(appState.isPinned ? String(localized: "Unpin window") : String(localized: "Keep window on top"))
    }

    // MARK: editor

    private var editorCard: some View {
        TextEditor(text: $draft)
            .font(.system(size: 15))
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(minHeight: 110, maxHeight: 190)
            .background(.background.opacity(0.45), in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Type here, or select text anywhere and press ⌥⌘D")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20)
                        .padding(.leading, 18)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !draft.isEmpty {
                    Button {
                        draft = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Clear")
                }
            }
    }

    // MARK: result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !appState.lastSourceLang.isEmpty {
                    HStack(spacing: 4) {
                        Text(Self.langDisplayName(appState.lastSourceLang))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(Self.langDisplayName(appState.lastTargetLang))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.45), in: .capsule)
                }
                Spacer()
                if appState.isTranslating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(appState.currentAction.progressiveVerb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if !appState.translatedText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.translatedText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Copy result")
                    .transition(.opacity)
                }
            }

            Divider()
                .opacity(0.35)

            ScrollView {
                Group {
                    if let error = appState.errorMessage {
                        Label {
                            Text(error).textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    } else if appState.translatedText.isEmpty {
                        Text(appState.isTranslating ? " " : "Translation appears here")
                            .font(.system(size: 14))
                            .foregroundStyle(.quaternary)
                    } else {
                        Text(
                            (try? AttributedString(
                                markdown: appState.translatedText,
                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                ?? AttributedString(appState.translatedText)
                        )
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .contentTransition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .animation(.spring(duration: 0.3), value: appState.isTranslating)
    }

    // MARK: footer — settings + model at leading, actions at trailing

    private var footerBar: some View {
        HStack(spacing: 10) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Settings")

            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text(settingsStore.settings.apiModel)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.45), in: .capsule)
            .help("Current model")

            Spacer()

            Button("History", systemImage: "clock.arrow.circlepath") {
                showHistory = true
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .help("Translation history")
            .sheet(isPresented: $showHistory) {
                HistoryView { item in
                    appState.restore(item)
                    draft = item.sourceText
                }
            }

            Button(appState.currentAction.actionVerb, systemImage: appState.currentAction.icon,
                   action: translateDraft)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func translateDraft() {
        appState.inputText = draft
        appState.translate()
    }

    private static func langDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
