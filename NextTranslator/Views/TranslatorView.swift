import SwiftUI

/// A cursive flourish. Drawn with `trim` so a pen stroke sweeps across,
/// leaves the curve behind, then flows out through the tail.
private struct WritingCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: 0.02 * w, y: 0.72 * h))
        p.addCurve(
            to: CGPoint(x: 0.30 * w, y: 0.34 * h),
            control1: CGPoint(x: 0.10 * w, y: 0.98 * h),
            control2: CGPoint(x: 0.20 * w, y: 0.08 * h))
        p.addCurve(
            to: CGPoint(x: 0.52 * w, y: 0.70 * h),
            control1: CGPoint(x: 0.40 * w, y: 0.62 * h),
            control2: CGPoint(x: 0.43 * w, y: 0.98 * h))
        p.addCurve(
            to: CGPoint(x: 0.76 * w, y: 0.36 * h),
            control1: CGPoint(x: 0.61 * w, y: 0.40 * h),
            control2: CGPoint(x: 0.66 * w, y: 0.12 * h))
        p.addCurve(
            to: CGPoint(x: 0.98 * w, y: 0.52 * h),
            control1: CGPoint(x: 0.86 * w, y: 0.62 * h),
            control2: CGPoint(x: 0.93 * w, y: 0.40 * h))
        return p
    }
}

private struct WritingIndicator: View {
    /// 0…1 draws the stroke in, 1…2 lets it flow out through the tail.
    @State private var phase: CGFloat = 0

    var body: some View {
        WritingCurveShape()
            .trim(from: max(phase - 1, 0), to: min(phase, 1))
            .stroke(
                .secondary,
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 56, height: 15)
            .task {
                while !Task.isCancelled {
                    phase = 0
                    withAnimation(.easeInOut(duration: 1.05)) { phase = 1 }
                    try? await Task.sleep(for: .seconds(1.15))
                    withAnimation(.easeInOut(duration: 0.75)) { phase = 2 }
                    try? await Task.sleep(for: .seconds(0.9))
                }
            }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 0.06 * rect.width, y: rect.minY + 0.58 * rect.height))
        p.addLine(to: CGPoint(x: rect.minX + 0.38 * rect.width, y: rect.maxY - 0.06 * rect.height))
        p.addLine(to: CGPoint(x: rect.maxX - 0.04 * rect.width, y: rect.minY + 0.08 * rect.height))
        return p
    }
}

/// Apple-style solid blue checkmark that draws itself on appearance.
private struct DrawnCheckmark: View {
    var width: CGFloat = 15
    @State private var progress: CGFloat = 0

    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(
                .blue,
                style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
            )
            .frame(width: width, height: width * 0.74)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) { progress = 1 }
            }
    }
}

private struct WordRollModifier: ViewModifier {
    var blur: CGFloat
    var opacity: Double
    var offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    /// The incoming word rises from below through a soft blur while the old
    /// one lifts away — the words keep moving while the model does.
    fileprivate static var wordRoll: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: WordRollModifier(blur: 3, opacity: 0, offsetY: 9),
                identity: WordRollModifier(blur: 0, opacity: 1, offsetY: 0)),
            removal: .modifier(
                active: WordRollModifier(blur: 3, opacity: 0, offsetY: -9),
                identity: WordRollModifier(blur: 0, opacity: 1, offsetY: 0)))
    }
}

/// Shows one status phrase at a time and rolls to the next every couple of
/// seconds. Each round walks a fresh shuffle of the bank, never repeating the
/// word already on screen back to back.
private struct CyclingStatusText: View {
    let phrases: [String]
    @State private var phrase: String = ""

    var body: some View {
        let displayed = phrase.isEmpty ? (phrases.first ?? "") : phrase
        // Hidden copies of every phrase pin the container to the widest one,
        // and the visible word is leading-aligned inside it — so neither the
        // indicator ahead of it nor the word's own left edge ever shifts.
        ZStack(alignment: .leading) {
            ForEach(phrases, id: \.self) { word in
                Text(word).fixedSize().hidden()
            }
            Text(displayed)
                .fixedSize()
                .id(displayed)
                .transition(.wordRoll)
        }
        .task(id: phrases) {
            guard let first = phrases.first else { return }
            var shown = first
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) { phrase = first }
            guard phrases.count > 1 else { return }
            while !Task.isCancelled {
                var deck = phrases.shuffled()
                if deck.first == shown {
                    deck.swapAt(0, deck.count - 1)
                }
                for word in deck {
                    try? await Task.sleep(for: .seconds(2.4))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(duration: 0.6, bounce: 0.2)) { phrase = word }
                    shown = word
                }
            }
        }
    }
}

extension TranslatorAction {
    /// User-facing name. Built-ins keep the user's custom name when edited.
    var localizedName: String {
        switch builtinMode {
        case "translate" where name.isEmpty || name == "Translate":
            return String(localized: "Translate")
        case "polishing" where name.isEmpty || name == "Polish":
            return String(localized: "Polish")
        case "summarize" where name.isEmpty || name == "Summarize":
            return String(localized: "Summarize")
        case "explain" where name.isEmpty || name == "Explain":
            return String(localized: "Explain")
        case "quick-ask" where name.isEmpty || name == "Quick Ask":
            return String(localized: "Quick Ask")
        default:
            return name
        }
    }

    /// Verb shown on the action button ("Translate", "Polish", …).
    var actionVerb: String {
        switch builtinMode {
        case "translate": return String(localized: "Translate")
        case "polishing": return String(localized: "Polish")
        case "summarize": return String(localized: "Summarize")
        case "explain": return String(localized: "Explain")
        case "quick-ask": return String(localized: "Ask")
        default: return name
        }
    }

    /// Status word while streaming ("Translating…"); user-overridable.
    var workingText: String {
        if !workingLabel.isEmpty { return workingLabel }
        switch builtinMode {
        case "translate": return String(localized: "Translating…")
        case "polishing": return String(localized: "Polishing…")
        case "summarize": return String(localized: "Summarizing…")
        case "explain": return String(localized: "Explaining…")
        case "quick-ask": return String(localized: "Answering…")
        default: return name + "…"
        }
    }

    /// Rotating status phrases while a built-in action streams. The canonical
    /// verb leads; the deck behind it reshuffles every round. A one-element
    /// bank (user-overridden label or custom action) shows statically.
    var workingPhrases: [String] {
        guard workingLabel.isEmpty else { return [workingLabel] }
        switch builtinMode {
        case "translate":
            return [
                String(localized: "Translating…"),
                String(localized: "Interpreting…"),
                String(localized: "Transposing…"),
                String(localized: "Deliberating…"),
                String(localized: "Weighing…"),
                String(localized: "Rephrasing…"),
                String(localized: "Recasting…"),
                String(localized: "Wordsmithing…"),
                String(localized: "Decoding…"),
                String(localized: "Rendering…"),
                String(localized: "Bridging…"),
                String(localized: "Untangling…"),
            ]
        case "polishing":
            return [
                String(localized: "Polishing…"),
                String(localized: "Refining…"),
                String(localized: "Smoothing…"),
                String(localized: "Tightening…"),
                String(localized: "Trimming…"),
                String(localized: "Sharpening…"),
                String(localized: "Elevating…"),
                String(localized: "Buffing…"),
                String(localized: "Reshaping…"),
                String(localized: "Balancing…"),
                String(localized: "Pruning…"),
                String(localized: "Burnishing…"),
            ]
        case "summarize":
            return [
                String(localized: "Summarizing…"),
                String(localized: "Distilling…"),
                String(localized: "Condensing…"),
                String(localized: "Sifting…"),
                String(localized: "Skimming…"),
                String(localized: "Extracting…"),
                String(localized: "Gathering…"),
                String(localized: "Winnowing…"),
                String(localized: "Outlining…"),
                String(localized: "Digesting…"),
                String(localized: "Crystallizing…"),
                String(localized: "Recapping…"),
            ]
        case "explain":
            return [
                String(localized: "Explaining…"),
                String(localized: "Unpacking…"),
                String(localized: "Clarifying…"),
                String(localized: "Tracing…"),
                String(localized: "Illuminating…"),
                String(localized: "Demystifying…"),
                String(localized: "Connecting…"),
                String(localized: "Digging…"),
                String(localized: "Simplifying…"),
                String(localized: "Annotating…"),
                String(localized: "Elaborating…"),
                String(localized: "Probing…"),
            ]
        case "quick-ask":
            return [
                String(localized: "Answering…"),
                String(localized: "Thinking…"),
                String(localized: "Pondering…"),
                String(localized: "Reasoning…"),
                String(localized: "Mulling…"),
                String(localized: "Deducing…"),
                String(localized: "Recalling…"),
                String(localized: "Drafting…"),
                String(localized: "Verifying…"),
                String(localized: "Cogitating…"),
                String(localized: "Synthesizing…"),
                String(localized: "Percolating…"),
            ]
        default:
            return [workingText]
        }
    }

    /// Empty-state hint in the result card, matching the action.
    var placeholderText: String {
        switch builtinMode {
        case "translate": return String(localized: "Translation appears here")
        case "polishing": return String(localized: "Polished text appears here")
        case "summarize": return String(localized: "Summary appears here")
        case "explain": return String(localized: "Explanation appears here")
        case "quick-ask": return String(localized: "Answer appears here")
        default: return String(localized: "Result appears here")
        }
    }

    /// Status word after completion ("Translated"); user-overridable.
    var doneText: String {
        if !doneLabel.isEmpty { return doneLabel }
        switch builtinMode {
        case "translate": return String(localized: "Translated")
        case "polishing": return String(localized: "Polished")
        case "summarize": return String(localized: "Summarized")
        case "explain": return String(localized: "Explained")
        case "quick-ask": return String(localized: "Answered")
        default: return String(localized: "Done")
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
    @State private var splitterHovered = false
    @State private var splitterDragBase: CGFloat?
    @State private var splitterDragHeight: CGFloat?
    @Environment(\.openSettings) private var openSettings
    @Namespace private var glassNamespace

    var body: some View {
        VStack(spacing: 12) {
            headerBar
            splitArea
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
            appState.applyWindowTraits()
            appState.openSettingsBridge = { openSettings() }
        }
        .onExitCommand {
            appState.hideTranslatorWindow()
        }
        .onChange(of: actionStore.actions) { _, actions in
            if !actions.contains(where: { $0.id == appState.currentAction.id }), let first = actions.first {
                appState.currentAction = first
            }
        }
    }

    // MARK: header — action pills (selected expands to icon+label), pin trailing

    private var headerBar: some View {
        GlassEffectContainer(spacing: 8) {
            actionsArea
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
                    HStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(actionStore.actions) { action in
                                    actionPill(action, forceIconOnly: true)
                                }
                            }
                        }
                        pinButton
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
                pinButton
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
                pinButton
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

    /// The pin participates in the same justified spacing chain as the action
    /// pills, anchored at the trailing end.
    private func justifiedPills(forceIconOnly: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(actionStore.actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Spacer(minLength: 6)
                }
                actionPill(action, forceIconOnly: forceIconOnly)
            }
            Spacer(minLength: 6)
            pinButton
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
                    Text(action.localizedName)
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
        .help(action.localizedName)
    }

    /// Same metrics as an icon-only action pill so the top row reads as one
    /// consistent family of controls.
    private var pinButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                appState.toggleAlwaysOnTop()
            }
        } label: {
            Image(systemName: appState.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: appState.isPinned ? .semibold : .medium))
                .foregroundStyle(appState.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(.capsule)
                .symbolEffect(.bounce, value: appState.isPinned)
        }
        .buttonStyle(.plain)
        .glassEffect(
            appState.isPinned ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .help(appState.isPinned ? String(localized: "Unpin window") : String(localized: "Keep window on top"))
    }

    // MARK: editor / result split

    private static let splitterHeight: CGFloat = 14
    private static let minEditorHeight: CGFloat = 88
    private static let minResultHeight: CGFloat = 132
    private static let defaultSplitFraction: Double = 0.44

    /// Editor above, result below, a draggable grabber between them. The
    /// fraction persists so the window reopens with the same balance.
    private var splitArea: some View {
        GeometryReader { geo in
            let available = geo.size.height - Self.splitterHeight
            let editorHeight = Self.clampedEditorHeight(
                splitterDragHeight
                    ?? available * CGFloat(settingsStore.settings.editorSplitFraction),
                available: available)
            VStack(spacing: 0) {
                editorCard
                    .frame(height: editorHeight)
                splitter(available: available, editorHeight: editorHeight)
                resultCard
            }
        }
    }

    /// Whole-point heights only: fractional card heights make every text run
    /// re-rasterise at subpixel offsets, which reads as jitter during drags.
    private static func clampedEditorHeight(_ height: CGFloat, available: CGFloat) -> CGFloat {
        let maxEditor = max(minEditorHeight, available - minResultHeight)
        return min(max(height, minEditorHeight), maxEditor).rounded()
    }

    /// Sheet-style grabber in the gap between the cards; it widens on hover,
    /// drags to rebalance, and double-clicks back to the default split.
    private func splitter(available: CGFloat, editorHeight: CGFloat) -> some View {
        let engaged = splitterHovered || splitterDragBase != nil
        return Capsule()
            .fill(.secondary.opacity(engaged ? 0.55 : 0.28))
            .frame(width: engaged ? 56 : 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.splitterHeight)
            .contentShape(.rect)
            .onHover { hovering in
                splitterHovered = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = splitterDragBase ?? editorHeight
                        splitterDragBase = base
                        NSCursor.resizeUpDown.set()
                        // Track in local state; publishing through the settings
                        // store every tick repaints every observer of it.
                        splitterDragHeight = Self.clampedEditorHeight(
                            base + value.translation.height, available: available)
                    }
                    .onEnded { _ in
                        if let height = splitterDragHeight, available > 0 {
                            settingsStore.settings.editorSplitFraction = Double(height / available)
                            try? settingsStore.save()
                        }
                        splitterDragBase = nil
                        splitterDragHeight = nil
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.4)) {
                    settingsStore.settings.editorSplitFraction = Self.defaultSplitFraction
                }
                try? settingsStore.save()
            }
            .animation(.spring(duration: 0.25), value: engaged)
            .help("Drag to resize, double-click to reset")
    }

    private var editorCard: some View {
        TextEditor(text: $draft)
            .font(.system(size: 15))
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(.background.opacity(0.45), in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    // Same font and insets as the TextEditor's first line so
                    // the caret and the placeholder sit on one baseline.
                    Text("Type here, or select text anywhere and press ⌥⌘D")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                        .padding(.leading, 17)
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

    /// Centered status: an animated writing gesture while streaming, a
    /// bouncing checkmark once the action finishes.
    @ViewBuilder private var statusIndicator: some View {
        if appState.isTranslating {
            HStack(spacing: 8) {
                WritingIndicator()
                CyclingStatusText(phrases: appState.currentAction.workingPhrases)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        } else if !appState.translatedText.isEmpty, appState.errorMessage == nil {
            HStack(spacing: 7) {
                DrawnCheckmark(width: 14)
                Text(appState.currentAction.doneText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                statusIndicator
                HStack {
                    Spacer()
                    if appState.isTranslating {
                        Button {
                            appState.stopTranslation()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Stop")
                        .transition(.opacity)
                    } else if !appState.translatedText.isEmpty {
                        copyButton
                    }
                }
            }
            .frame(height: 20)
            .animation(.spring(duration: 0.35), value: appState.isTranslating)

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
                        Text(appState.isTranslating ? " " : appState.currentAction.placeholderText)
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
            withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
            Task {
                // Draw-on takes 0.35s; hold the finished checkmark a full
                // second before anything else happens.
                try? await Task.sleep(for: .seconds(1.35))
                withAnimation(.easeOut(duration: 0.25)) { justCopied = false }
            }
        } label: {
            ZStack {
                if justCopied {
                    DrawnCheckmark(width: 13)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 15, height: 13)
        }
        .buttonStyle(.plain)
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

}
