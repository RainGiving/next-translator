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

    /// Chip text in the result header. Empty means "use the built-in default";
    /// the translate action's default is the dynamic language pair chip.
    var defaultResultLabel: String {
        switch builtinMode {
        case "polishing": return String(localized: "Polished")
        case "summarize": return String(localized: "Summary")
        case "analyze": return String(localized: "Analysis")
        case "explain-code": return String(localized: "Code Explanation")
        default: return name
        }
    }
}

struct TranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var actionStore = ActionStore.shared
    @State private var draft: String = ""
    @State private var showHistory = false
    @State private var showModelPicker = false
    @State private var justCopied = false
    @State private var expandedPillsWidth: CGFloat = 0
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

    // MARK: header — action pills (selected expands to icon+label), pin trailing

    private var headerBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                actionsArea
                pinButton
            }
        }
    }

    private var actionsArea: some View {
        GeometryReader { geo in
            Group {
                if expandedPillsWidth <= geo.size.width {
                    justifiedPills(forceIconOnly: false)
                } else if iconPillsWidth <= geo.size.width {
                    justifiedPills(forceIconOnly: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(actionStore.actions) { action in
                                actionPill(action, forceIconOnly: true)
                            }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(measurementProbe)
    }

    /// Hidden fixed-size copies report natural widths of both layouts so the
    /// visible row picks the richest variant that fits.
    private var measurementProbe: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(actionStore.actions) { action in
                    actionPill(action, forceIconOnly: false)
                }
            }
            .fixedSize()
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { expandedPillsWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in expandedPillsWidth = w }
                }
            )
            HStack(spacing: 6) {
                ForEach(actionStore.actions) { action in
                    actionPill(action, forceIconOnly: true)
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

    private func justifiedPills(forceIconOnly: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(actionStore.actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Spacer(minLength: 6)
                }
                actionPill(action, forceIconOnly: forceIconOnly)
            }
        }
    }

    /// The selected pill grows into icon+label; its neighbours get squeezed
    /// aside with a bouncy spring while glass shapes morph.
    private func actionPill(_ action: TranslatorAction, forceIconOnly: Bool) -> some View {
        let selected = appState.currentAction.id == action.id
        let expanded = selected && !forceIconOnly
        return Button {
            if appState.currentAction.id != action.id {
                withAnimation(.spring(duration: 0.45, bounce: 0.32)) {
                    appState.currentAction = action
                }
            }
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translateDraft()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                if expanded {
                    Text(action.name)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.5, anchor: .leading)),
                                removal: .opacity
                            ))
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, expanded ? 13 : 10)
            .padding(.vertical, 8)
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
                .symbolEffect(.bounce, value: appState.isPinned)
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
                        withAnimation(.spring(duration: 0.25)) { draft = "" }
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

    @ViewBuilder private var resultHeaderChip: some View {
        let action = appState.currentAction
        if action.builtinMode == TranslateMode.translate.rawValue, action.resultLabel.isEmpty {
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
        } else {
            Label(
                action.resultLabel.isEmpty ? action.defaultResultLabel : action.resultLabel,
                systemImage: action.icon
            )
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.45), in: .capsule)
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if appState.isTranslating || !appState.translatedText.isEmpty {
                    resultHeaderChip
                        .contentTransition(.opacity)
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
                    copyButton
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

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(appState.translatedText, forType: .string)
            withAnimation(.spring(duration: 0.3)) { justCopied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.spring(duration: 0.3)) { justCopied = false }
            }
        } label: {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: justCopied ? .bold : .regular))
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
        .foregroundStyle(justCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        .disabled(justCopied)
        .help("Copy result")
        .transition(.opacity)
    }

    // MARK: footer — settings/model/history leading, fixed-width action trailing

    private var footerBar: some View {
        HStack(spacing: 8) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Settings")

            Button {
                appState.refreshModels()
                showModelPicker = true
            } label: {
                Label(settingsStore.settings.apiModel, systemImage: "cpu")
                    .font(.caption)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Switch model")
            .popover(isPresented: $showModelPicker, arrowEdge: .top) {
                modelPicker
            }

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

            Spacer()

            actionButton
        }
    }

    /// Fixed-width action button: invisible copies of every action's label
    /// size the button to the longest one, so switching actions never makes
    /// it jump around; the visible label stays centered.
    private var actionButton: some View {
        Button(action: translateDraft) {
            ZStack {
                ForEach(actionStore.actions) { action in
                    Label(action.actionVerb, systemImage: action.icon)
                        .hidden()
                }
                Label(appState.currentAction.actionVerb, systemImage: appState.currentAction.icon)
                    .contentTransition(.opacity)
            }
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .animation(.spring(duration: 0.3), value: appState.currentAction.id)
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Model")
                    .font(.headline)
                Spacer()
                if appState.isLoadingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        appState.refreshModels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reload model list")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.4)

            if let error = appState.modelsError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(12)
            } else if appState.availableModels.isEmpty && !appState.isLoadingModels {
                Text("No models reported by this provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.availableModels, id: \.self) { model in
                            Button {
                                appState.selectModel(model)
                                showModelPicker = false
                            } label: {
                                HStack {
                                    Text(model)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Spacer()
                                    if model == settingsStore.settings.apiModel {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(.rect)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .background(
                                model == settingsStore.settings.apiModel
                                    ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear),
                                in: .rect(cornerRadius: 6)
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: 280, height: 340)
    }

    private func translateDraft() {
        appState.inputText = draft
        appState.translate()
    }

    private static func langDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
