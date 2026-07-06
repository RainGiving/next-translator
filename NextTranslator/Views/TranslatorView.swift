import SwiftUI

/// Skeleton translator window: proves out the Liquid Glass chrome.
/// The full editor / mode bar / streaming result lands in the next phase.
struct TranslatorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $draft)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 140)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))

            HStack {
                Text("Next Translator")
                    .font(.headline)
                Spacer()
                Button("Translate", systemImage: "translate") {}
                    .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 520)
        .onChange(of: appState.querySeq) {
            draft = appState.inputText
        }
    }
}
