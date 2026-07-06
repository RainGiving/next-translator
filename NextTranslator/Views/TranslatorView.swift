import SwiftUI

extension TranslateMode {
    var icon: String {
        switch self {
        case .translate: return "translate"
        case .polishing: return "wand.and.stars"
        case .summarize: return "doc.plaintext"
        case .analyze: return "sparkle.magnifyingglass"
        case .explainCode: return "curlybraces"
        }
    }
}

struct TranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settingsStore = SettingsStore.shared
    @State private var draft: String = ""
    @State private var showHistory = false
    @Namespace private var glassNamespace

    var body: some View {
        VStack(spacing: 12) {
            headerBar
            editorCard
            resultCard
            footerBar
        }
        .padding(14)
        .frame(minWidth: 580, minHeight: 560)
        .containerBackground(.thinMaterial, for: .window)
        .onChange(of: appState.querySeq) {
            draft = appState.inputText
        }
        .onAppear {
            draft = appState.inputText
        }
    }

    // MARK: header — glass mode pills, brand at the trailing edge

    private var headerBar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(TranslateMode.allCases) { mode in
                    modePill(mode)
                }
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Next Translator")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func modePill(_ mode: TranslateMode) -> some View {
        let selected = appState.mode == mode
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                appState.mode = mode
            }
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                translateDraft()
            }
        } label: {
            Label(mode.displayName, systemImage: mode.icon)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? .regular.tint(.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .glassEffectID(mode.id, in: glassNamespace)
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
                        Text("Translating…")
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

            Button("Translate", systemImage: "translate", action: translateDraft)
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
