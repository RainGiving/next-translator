import SwiftUI

struct TranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: String = ""
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 12) {
            modeBar

            TextEditor(text: $draft)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 110, maxHeight: 180)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
                .onSubmit(translateDraft)

            resultCard

            footerBar
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 540)
        .containerBackground(.ultraThinMaterial, for: .window)
        .onChange(of: appState.querySeq) {
            draft = appState.inputText
        }
        .onAppear {
            draft = appState.inputText
        }
    }

    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(TranslateMode.allCases) { mode in
                Button {
                    appState.mode = mode
                    if !draft.isEmpty {
                        translateDraft()
                    }
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: appState.mode == mode ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(
                    appState.mode == mode ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                    in: .capsule
                )
            }
            Spacer()
        }
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var resultCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error = appState.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if appState.translatedText.isEmpty && appState.isTranslating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Translating…").foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        (try? AttributedString(
                            markdown: appState.translatedText,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                            ?? AttributedString(appState.translatedText)
                    )
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .animation(.spring(duration: 0.35), value: appState.isTranslating)
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Text("Next Translator")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
            if !appState.translatedText.isEmpty {
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.translatedText, forType: .string)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            Button("Translate", systemImage: "translate", action: translateDraft)
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func translateDraft() {
        appState.inputText = draft
        appState.translate()
    }
}
