import SwiftUI

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @Environment(\.dismiss) private var dismiss
    let onRestore: (HistoryItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                if !store.items.isEmpty {
                    Button("Clear", systemImage: "trash", role: .destructive) {
                        store.clear()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if store.items.isEmpty {
                ContentUnavailableView(
                    "No translations yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Finished translations show up here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(store.items) { item in
                    row(item)
                        .contentShape(.rect)
                        .onTapGesture {
                            onRestore(item)
                            dismiss()
                        }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.delete(id: item.id)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 480, height: 440)
        .presentationBackground(.ultraThinMaterial)
    }

    private func row(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(Self.modeDisplayName(item.mode))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.16), in: .capsule)
                Text("\(item.sourceLang) → \(item.targetLang)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(item.date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(item.sourceText)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text(item.translatedText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }

    /// Entries recorded by retired built-in modes keep a readable badge.
    private static func modeDisplayName(_ mode: String) -> String {
        if let current = TranslateMode(rawValue: mode) {
            return current.displayName
        }
        switch mode {
        case "analyze": return String(localized: "Analyze")
        case "explain-code": return String(localized: "Explain Code")
        default: return mode
        }
    }
}
