import SwiftUI

struct ActionsSettingsView: View {
    @ObservedObject private var store = ActionStore.shared
    @State private var selection: TranslatorAction.ID?
    @State private var editorContext: ActionEditorContext?
    @State private var deleteConfirmationAction: TranslatorAction?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.actions) { action in
                    actionRow(action)
                        .tag(action.id)
                        .contentShape(.rect)
                        .onTapGesture(count: 2) {
                            beginEditing(action)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") {
                                beginEditing(action)
                            }

                            Button("Delete", systemImage: "trash", role: .destructive) {
                                requestDelete(action)
                            }
                        }
                }
                .onMove(perform: store.move)
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 8) {
                Button {
                    beginAdding()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Action")

                Button {
                    if let action: TranslatorAction = selectedAction {
                        beginEditing(action)
                    }
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(selectedAction == nil)
                .help("Edit Action")

                Button {
                    store.restoreMissingBuiltins()
                } label: {
                    Label("Restore Built-ins", systemImage: "arrow.counterclockwise")
                }
                .disabled(!canRestoreBuiltins)
                .help("Restore Missing Built-in Actions")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(item: $editorContext) { context in
            ActionEditorView(action: context.action) { savedAction in
                if context.isNew {
                    store.add(savedAction)
                } else {
                    store.update(savedAction)
                }
                selection = savedAction.id
                editorContext = nil
            }
        }
        .confirmationDialog(
            "Delete Built-in Action?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let action: TranslatorAction = deleteConfirmationAction {
                    delete(action)
                }
                deleteConfirmationAction = nil
            }

            Button("Cancel", role: .cancel) {
                deleteConfirmationAction = nil
            }
        } message: {
            Text("This built-in action can be restored later.")
        }
    }

    private var selectedAction: TranslatorAction? {
        guard let selection else { return nil }

        return store.actions.first { action in
            action.id == selection
        }
    }

    private var canRestoreBuiltins: Bool {
        let presentModes: Set<String> = Set(store.actions.compactMap(\.builtinMode))
        return Self.builtinModes.contains { mode in
            !presentModes.contains(mode)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deleteConfirmationAction != nil },
            set: { isPresented in
                if !isPresented {
                    deleteConfirmationAction = nil
                }
            }
        )
    }

    private func actionRow(_ action: TranslatorAction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(action.localizedName.isEmpty ? String(localized: "Untitled Action") : action.localizedName)
                .lineLimit(1)

            Spacer()

            if action.isBuiltin {
                Text("Built-in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func beginAdding() {
        editorContext = ActionEditorContext(
            action: TranslatorAction(
                id: UUID(),
                name: "",
                icon: "star",
                builtinMode: nil,
                rolePrompt: "",
                commandPrompt: "",
                workingLabel: "",
                doneLabel: ""
            ),
            isNew: true
        )
    }

    private func beginEditing(_ action: TranslatorAction) {
        editorContext = ActionEditorContext(action: action, isNew: false)
    }

    private func requestDelete(_ action: TranslatorAction) {
        if action.isBuiltin {
            deleteConfirmationAction = action
        } else {
            delete(action)
        }
    }

    private func delete(_ action: TranslatorAction) {
        store.delete(id: action.id)
        if selection == action.id {
            selection = nil
        }
    }

    private static let builtinModes: [String] = [
        "translate",
        "polishing",
        "summarize",
        "explain",
        "quick-ask",
    ]
}

struct ActionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let action: TranslatorAction
    private let onSave: (TranslatorAction) -> Void

    @State private var name: String
    @State private var icon: String
    @State private var workingLabel: String
    @State private var doneLabel: String
    @State private var rolePrompt: String
    @State private var commandPrompt: String
    @State private var showingSymbolPicker: Bool = false

    init(action: TranslatorAction, onSave: @escaping (TranslatorAction) -> Void) {
        self.action = action
        self.onSave = onSave
        self._name = State(initialValue: action.name)
        self._icon = State(initialValue: action.icon)
        self._workingLabel = State(initialValue: action.workingLabel)
        self._doneLabel = State(initialValue: action.doneLabel)
        self._rolePrompt = State(initialValue: action.rolePrompt)
        self._commandPrompt = State(initialValue: action.commandPrompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                TextField(
                    "Working label",
                    text: $workingLabel,
                    prompt: Text("Working status label. Leave blank to use the default, for example Translating…")
                )
                    .textFieldStyle(.roundedBorder)

                TextField(
                    "Done label",
                    text: $doneLabel,
                    prompt: Text("Done status label. Leave blank to use the default, for example Translated")
                )
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Text("Icon")
                    .frame(width: 110, alignment: .leading)

                Button {
                    showingSymbolPicker.toggle()
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .frame(width: 28, height: 28)
                }
                .popover(isPresented: $showingSymbolPicker, arrowEdge: .bottom) {
                    SymbolPickerView(selection: $icon)
                }

                Text(icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }

            if action.isBuiltin {
                Text("You can edit built-in prompts. Reset to Defaults restores the factory prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            promptEditor(title: "Role Prompt", text: $rolePrompt, height: 90)
            promptEditor(title: "Command Prompt", text: $commandPrompt, height: 70)

            Text("Available variables: ${text}, ${sourceLang}, ${targetLang}")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if action.isBuiltin {
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func promptEditor(title: LocalizedStringKey, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: height)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
                }
        }
    }

    private func save() {
        var savedAction: TranslatorAction = action
        savedAction.name = trimmedName
        savedAction.icon = icon
        savedAction.workingLabel = workingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        savedAction.doneLabel = doneLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        savedAction.rolePrompt = rolePrompt
        savedAction.commandPrompt = commandPrompt
        onSave(savedAction)
    }

    private func resetToDefaults() {
        guard let mode: String = action.builtinMode,
              var defaultAction: TranslatorAction = ActionStore.canonicalBuiltin(mode: mode)
        else {
            return
        }

        defaultAction.id = action.id
        onSave(defaultAction)
    }
}

private struct ActionEditorContext: Identifiable {
    let action: TranslatorAction
    let isNew: Bool

    var id: UUID { action.id }
}
