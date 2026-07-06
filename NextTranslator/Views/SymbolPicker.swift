import SwiftUI

enum SymbolLibrary {
    static let symbols: [String] = [
        "translate",
        "character",
        "character.book.closed",
        "text.book.closed",
        "textformat",
        "textformat.size",
        "textformat.alt",
        "textformat.abc",
        "textformat.abc.dottedunderline",
        "textformat.subscript",
        "textformat.superscript",
        "text.alignleft",
        "text.aligncenter",
        "text.alignright",
        "text.justify",
        "text.magnifyingglass",
        "list.bullet",
        "list.number",
        "list.bullet.rectangle",
        "paragraphsign",
        "quote.opening",
        "quote.closing",
        "doc",
        "doc.text",
        "doc.plaintext",
        "doc.richtext",
        "doc.badge.plus",
        "doc.on.doc",
        "clipboard",
        "book",
        "book.closed",
        "books.vertical",
        "pencil",
        "pencil.line",
        "pencil.and.outline",
        "highlighter",
        "eraser",
        "signature",
        "scribble",
        "scissors",
        "paintbrush",
        "paintpalette",
        "wrench.and.screwdriver",
        "hammer",
        "gearshape",
        "slider.horizontal.3",
        "line.3.horizontal.decrease.circle",
        "magnifyingglass",
        "sparkle.magnifyingglass",
        "sparkles",
        "wand.and.stars",
        "wand.and.rays",
        "lightbulb",
        "lightbulb.fill",
        "brain",
        "brain.head.profile",
        "graduationcap",
        "graduationcap.fill",
        "globe",
        "globe.americas",
        "globe.europe.africa",
        "globe.asia.australia",
        "network",
        "map",
        "mappin",
        "mappin.and.ellipse",
        "star",
        "star.fill",
        "bookmark",
        "bookmark.fill",
        "tag",
        "flag",
        "pin",
        "paperclip",
        "link",
        "bubble.left",
        "bubble.right",
        "text.bubble",
        "quote.bubble",
        "ellipsis.bubble",
        "message",
        "envelope",
        "at",
        "paperplane",
        "checkmark",
        "checkmark.circle",
        "checkmark.seal",
        "xmark",
        "xmark.circle",
        "exclamationmark.triangle",
        "info.circle",
        "questionmark.circle",
        "plus",
        "plus.circle",
        "minus.circle",
        "ellipsis",
        "ellipsis.circle",
        "arrow.left",
        "arrow.right",
        "arrow.up",
        "arrow.down",
        "arrow.left.circle",
        "arrow.right.circle",
        "arrow.left.arrow.right",
        "arrow.up.arrow.down",
        "arrow.clockwise",
        "arrow.counterclockwise",
        "arrow.triangle.2.circlepath",
        "arrow.2.squarepath",
        "arrow.turn.up.left",
        "arrow.turn.up.right",
        "arrow.uturn.left",
        "arrow.uturn.right",
        "arrow.down.doc",
        "arrow.up.doc",
        "square.and.pencil",
        "square.and.arrow.up",
        "square.and.arrow.down",
        "tray",
        "tray.fill",
        "tray.and.arrow.down",
        "tray.and.arrow.up",
        "folder",
        "archivebox",
        "externaldrive",
        "lock",
        "lock.open",
        "key",
        "shield",
        "eye",
        "eye.slash",
        "curlybraces",
        "chevron.left.forwardslash.chevron.right",
        "terminal",
        "keyboard",
        "command",
        "option",
        "control",
        "shift",
        "escape",
        "return",
        "function",
        "sum",
        "number",
        "percent",
        "calendar",
        "clock",
        "timer",
        "hourglass",
    ]
}

struct SymbolPickerView: View {
    @Binding var selection: String
    @State private var searchText: String = ""

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 36), spacing: 8),
    ]

    private var filteredSymbols: [String] {
        let query: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SymbolLibrary.symbols }

        return SymbolLibrary.symbols.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search Symbols", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        symbolButton(symbol)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(width: 340, height: 320)
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected: Bool = selection == symbol

        return Button {
            selection = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .help(symbol)
    }
}
