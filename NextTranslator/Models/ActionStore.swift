import Combine
import Foundation

struct TranslatorAction: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var builtinMode: String?
    var rolePrompt: String
    var commandPrompt: String
    var workingLabel: String
    var doneLabel: String

    var isBuiltin: Bool { builtinMode != nil }

    init(
        id: UUID,
        name: String,
        icon: String,
        builtinMode: String?,
        rolePrompt: String,
        commandPrompt: String,
        workingLabel: String = "",
        doneLabel: String = ""
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.builtinMode = builtinMode
        self.rolePrompt = rolePrompt
        self.commandPrompt = commandPrompt
        self.workingLabel = workingLabel
        self.doneLabel = doneLabel
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "star"
        self.builtinMode = try container.decodeIfPresent(String.self, forKey: .builtinMode)
        self.rolePrompt = try container.decodeIfPresent(String.self, forKey: .rolePrompt) ?? ""
        self.commandPrompt = try container.decodeIfPresent(String.self, forKey: .commandPrompt) ?? ""
        self.workingLabel = try container.decodeIfPresent(String.self, forKey: .workingLabel) ?? ""
        self.doneLabel = try container.decodeIfPresent(String.self, forKey: .doneLabel) ?? ""
    }
}

@MainActor
final class ActionStore: ObservableObject {
    static let shared: ActionStore = ActionStore()

    @Published private(set) var actions: [TranslatorAction]

    private let fileManager: FileManager
    private let actionsFileURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.actionsFileURL = Self.makeActionsFileURL(fileManager: fileManager)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let fileExists: Bool = fileManager.fileExists(atPath: actionsFileURL.path)
        var loadedActions: [TranslatorAction] = fileExists
            ? (try? Self.loadActions(from: actionsFileURL, decoder: decoder)) ?? []
            : Self.builtinSpecs.map { $0.action() }

        var migrated = false

        // Upgrade path: "analyze" and "explain-code" were retired in favour of
        // "explain" and "quick-ask". Dropping a retired action marks the file
        // as pre-upgrade, and only then are the two new modes seeded, so
        // built-ins the user deletes afterwards stay deleted.
        let withoutRetired: [TranslatorAction] = loadedActions.filter { action in
            guard let mode = action.builtinMode else { return true }
            return !Self.retiredBuiltinModes.contains(mode)
        }
        if withoutRetired.count != loadedActions.count {
            loadedActions = Self.restoringMissingBuiltins(
                in: withoutRetired, limitedTo: ["explain", "quick-ask"])
            migrated = true
        }

        // Upgrade path: earlier versions seeded built-ins with empty prompts.
        // Fill them with the canonical templates so the actions work (and are
        // inspectable) out of the box without a manual Reset to Defaults.
        for index in loadedActions.indices {
            let action = loadedActions[index]
            if let mode = action.builtinMode,
                action.rolePrompt.isEmpty, action.commandPrompt.isEmpty,
                let canonical = Self.canonicalBuiltin(mode: mode)
            {
                loadedActions[index].rolePrompt = canonical.rolePrompt
                loadedActions[index].commandPrompt = canonical.commandPrompt
                migrated = true
            }
        }

        self.actions = loadedActions

        if !fileExists || migrated {
            persist()
        }
    }

    func add(_ action: TranslatorAction) {
        actions.append(action)
        persist()
    }

    func update(_ action: TranslatorAction) {
        guard let index: Int = actions.firstIndex(where: { $0.id == action.id }) else { return }

        var updatedAction: TranslatorAction = action
        if let builtinMode: String = actions[index].builtinMode {
            updatedAction.id = actions[index].id
            updatedAction.builtinMode = builtinMode
        }

        actions[index] = updatedAction
        persist()
    }

    func delete(id: UUID) {
        guard let index: Int = actions.firstIndex(where: { $0.id == id }) else { return }

        actions.remove(at: index)
        persist()
    }

    func restoreMissingBuiltins() {
        let restoredActions: [TranslatorAction] = Self.restoringMissingBuiltins(in: actions)
        guard restoredActions != actions else { return }

        actions = restoredActions
        persist()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        let movingIndexes: [Int] = fromOffsets
            .filter { actions.indices.contains($0) }
            .sorted()
        guard !movingIndexes.isEmpty else { return }

        let movingIndexSet: Set<Int> = Set(movingIndexes)
        let movingActions: [TranslatorAction] = movingIndexes.map { actions[$0] }
        var remainingActions: [TranslatorAction] = actions.enumerated()
            .filter { !movingIndexSet.contains($0.offset) }
            .map(\.element)

        let removedBeforeDestination: Int = movingIndexes.filter { $0 < toOffset }.count
        let insertionIndex: Int = max(
            0,
            min(toOffset - removedBeforeDestination, remainingActions.count)
        )

        remainingActions.insert(contentsOf: movingActions, at: insertionIndex)
        guard remainingActions != actions else { return }

        actions = remainingActions
        persist()
    }

    private func persist() {
        do {
            let directoryURL: URL = actionsFileURL.deletingLastPathComponent()
            let data: Data = try encoder.encode(actions)

            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: actionsFileURL, options: [.atomic])
        } catch {
            Self.writeStandardError("Failed to write actions.json: \(error)\n")
        }
    }

    private static func restoringMissingBuiltins(
        in loadedActions: [TranslatorAction],
        limitedTo restorableModes: Set<String>? = nil
    ) -> [TranslatorAction] {
        var presentBuiltinModes: Set<String> = []
        var restoredActions: [TranslatorAction] = loadedActions

        for action: TranslatorAction in loadedActions {
            if let builtinMode: String = action.builtinMode,
               builtinSpecByMode[builtinMode] != nil {
                presentBuiltinModes.insert(builtinMode)
            }
        }

        for (specIndex, spec) in builtinSpecs.enumerated()
        where !presentBuiltinModes.contains(spec.mode)
            && restorableModes?.contains(spec.mode) ?? true {
            let insertionIndex: Int = missingBuiltinInsertionIndex(
                forBuiltinAt: specIndex,
                in: restoredActions
            )
            restoredActions.insert(spec.action(), at: insertionIndex)
        }

        return restoredActions
    }

    private static func missingBuiltinInsertionIndex(
        forBuiltinAt specIndex: Int,
        in actions: [TranslatorAction]
    ) -> Int {
        let builtinIndexesByMode: [String: Int] = Dictionary(
            uniqueKeysWithValues: builtinSpecs.enumerated().map { ($0.element.mode, $0.offset) }
        )

        if let nextBuiltinIndex: Int = actions.firstIndex(where: { action in
            guard let mode: String = action.builtinMode,
                  let index: Int = builtinIndexesByMode[mode]
            else {
                return false
            }
            return index > specIndex
        }) {
            return nextBuiltinIndex
        }

        if let previousBuiltinIndex: Int = actions.lastIndex(where: { action in
            guard let mode: String = action.builtinMode,
                  let index: Int = builtinIndexesByMode[mode]
            else {
                return false
            }
            return index < specIndex
        }) {
            return previousBuiltinIndex + 1
        }

        return min(specIndex, actions.count)
    }

    private static func loadActions(from url: URL, decoder: JSONDecoder) throws -> [TranslatorAction] {
        let data: Data = try Data(contentsOf: url)
        return try decoder.decode([TranslatorAction].self, from: data)
    }

    private static func makeActionsFileURL(fileManager: FileManager) -> URL {
        let applicationSupportURL: URL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupportURL
            .appendingPathComponent("com.nexttranslator.native", isDirectory: true)
            .appendingPathComponent("actions.json", isDirectory: false)
    }

    private static func writeStandardError(_ message: String) {
        guard let data: Data = message.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    static func canonicalBuiltin(mode: String) -> TranslatorAction? {
        builtinSpecByMode[mode]?.action()
    }

    private static let builtinSpecs: [BuiltinActionSpec] = [
        BuiltinActionSpec(
            mode: "translate",
            name: "Translate",
            icon: "translate",
            rolePrompt: """
            You are a professional translation engine. Translate faithfully and naturally from ${sourceLang} to ${targetLang}.
            """,
            commandPrompt: """
            Translate the following text from ${sourceLang} to ${targetLang}. Return only the translated text, with no explanation or extra comments:

            ${text}
            """
        ),
        BuiltinActionSpec(
            mode: "polishing",
            name: "Polish",
            icon: "wand.and.stars",
            rolePrompt: """
            You are an expert translator and editor. Edit text directly without explanation.
            """,
            commandPrompt: """
            Edit the following ${sourceLang} text to improve clarity, conciseness, and coherence, making it read like native writing. Return only the polished result:

            ${text}
            """
        ),
        BuiltinActionSpec(
            mode: "summarize",
            name: "Summarize",
            icon: "doc.plaintext",
            rolePrompt: """
            You are a professional text summarizer. Only summarize the text; do not interpret it.
            """,
            commandPrompt: """
            Summarize the following text concisely in ${targetLang}. Return only the summary:

            ${text}
            """
        ),
        BuiltinActionSpec(
            mode: "explain",
            name: "Explain",
            icon: "text.magnifyingglass",
            rolePrompt: """
            You are a knowledgeable explainer. Explain accurately and concisely in plain ${targetLang} that a curious reader can follow.
            """,
            commandPrompt: """
            Explain the following text in ${targetLang}. If it is a single word or term, explain its meaning and the concept behind it. If it is a sentence or passage, explain what it means, then briefly explain the important terms it contains. Return only the explanation:

            ${text}
            """
        ),
        BuiltinActionSpec(
            mode: "quick-ask",
            name: "Quick Ask",
            icon: "questionmark.bubble",
            rolePrompt: """
            You are a helpful assistant. Answer questions directly, accurately and concisely in ${targetLang}.
            """,
            commandPrompt: """
            Answer the following question concisely in ${targetLang}. Return only the answer:

            ${text}
            """
        ),
    ]

    /// Built-in modes shipped by earlier versions and since removed. Their
    /// persisted actions are dropped on load.
    static let retiredBuiltinModes: Set<String> = ["analyze", "explain-code"]

    private static let builtinSpecByMode: [String: BuiltinActionSpec] = Dictionary(
        uniqueKeysWithValues: builtinSpecs.map { ($0.mode, $0) }
    )
}

private struct BuiltinActionSpec: Hashable {
    let mode: String
    let name: String
    let icon: String
    let rolePrompt: String
    let commandPrompt: String

    func action() -> TranslatorAction {
        TranslatorAction(
            id: UUID(),
            name: name,
            icon: icon,
            builtinMode: mode,
            rolePrompt: rolePrompt,
            commandPrompt: commandPrompt,
            workingLabel: "",
            doneLabel: ""
        )
    }
}
