import Combine
import Foundation

struct TranslatorAction: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var icon: String
    var builtinMode: String?
    var rolePrompt: String
    var commandPrompt: String
    var resultLabel: String

    var isBuiltin: Bool { builtinMode != nil }

    init(
        id: UUID,
        name: String,
        icon: String,
        builtinMode: String?,
        rolePrompt: String,
        commandPrompt: String,
        resultLabel: String = ""
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.builtinMode = builtinMode
        self.rolePrompt = rolePrompt
        self.commandPrompt = commandPrompt
        self.resultLabel = resultLabel
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "star"
        self.builtinMode = try container.decodeIfPresent(String.self, forKey: .builtinMode)
        self.rolePrompt = try container.decodeIfPresent(String.self, forKey: .rolePrompt) ?? ""
        self.commandPrompt = try container.decodeIfPresent(String.self, forKey: .commandPrompt) ?? ""
        self.resultLabel = try container.decodeIfPresent(String.self, forKey: .resultLabel) ?? ""
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
        let loadedActions: [TranslatorAction] = fileExists
            ? (try? Self.loadActions(from: actionsFileURL, decoder: decoder))
            ?? []
            : []
        let normalizedActions: [TranslatorAction] = Self.normalizedActions(loadedActions)

        self.actions = normalizedActions

        if !fileExists || normalizedActions != loadedActions {
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
        guard let index: Int = actions.firstIndex(where: { $0.id == id }),
              !actions[index].isBuiltin
        else {
            return
        }

        actions.remove(at: index)
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

    private static func normalizedActions(_ loadedActions: [TranslatorAction]) -> [TranslatorAction] {
        var presentBuiltinModes: Set<String> = []
        var normalizedActions: [TranslatorAction] = loadedActions

        for action: TranslatorAction in loadedActions {
            if let builtinMode: String = action.builtinMode,
               builtinSpecByMode[builtinMode] != nil {
                presentBuiltinModes.insert(builtinMode)
            }
        }

        for (specIndex, spec) in builtinSpecs.enumerated() where !presentBuiltinModes.contains(spec.mode) {
            let insertionIndex: Int = missingBuiltinInsertionIndex(
                forBuiltinAt: specIndex,
                in: normalizedActions
            )
            normalizedActions.insert(spec.action(), at: insertionIndex)
        }

        return normalizedActions
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
        BuiltinActionSpec(mode: "translate", name: "Translate", icon: "translate"),
        BuiltinActionSpec(mode: "polishing", name: "Polish", icon: "wand.and.stars"),
        BuiltinActionSpec(mode: "summarize", name: "Summarize", icon: "doc.plaintext"),
        BuiltinActionSpec(mode: "analyze", name: "Analyze", icon: "sparkle.magnifyingglass"),
        BuiltinActionSpec(mode: "explain-code", name: "Explain Code", icon: "curlybraces"),
    ]

    private static let builtinSpecByMode: [String: BuiltinActionSpec] = Dictionary(
        uniqueKeysWithValues: builtinSpecs.map { ($0.mode, $0) }
    )
}

private struct BuiltinActionSpec: Hashable {
    let mode: String
    let name: String
    let icon: String

    func action() -> TranslatorAction {
        TranslatorAction(
            id: UUID(),
            name: name,
            icon: icon,
            builtinMode: mode,
            rolePrompt: "",
            commandPrompt: "",
            resultLabel: ""
        )
    }
}
