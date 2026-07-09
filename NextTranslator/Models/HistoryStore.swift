import Combine
import Foundation

struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let mode: String
    let sourceText: String
    let translatedText: String
    let sourceLang: String
    let targetLang: String
    /// Model that produced the result; nil on entries from older versions.
    let model: String?
    /// UUID of the custom action that ran; nil for built-ins and old entries.
    /// Custom action names are not unique, so cache lookups match on this.
    let actionID: String?

    init(
        id: UUID,
        date: Date,
        mode: String,
        sourceText: String,
        translatedText: String,
        sourceLang: String,
        targetLang: String,
        model: String? = nil,
        actionID: String? = nil
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.model = model
        self.actionID = actionID
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem]

    private let fileManager: FileManager
    private let historyFileURL: URL
    private let decoder: JSONDecoder
    private let persistenceQueue: DispatchQueue

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.historyFileURL = Self.makeHistoryFileURL(fileManager: fileManager)
        self.decoder = JSONDecoder()
        self.persistenceQueue = DispatchQueue(label: "com.nexttranslator.history.persistence", qos: .utility)

        decoder.dateDecodingStrategy = .iso8601

        if fileManager.fileExists(atPath: historyFileURL.path) {
            self.items = Self.loadItems(from: historyFileURL, decoder: decoder)
        } else {
            self.items = []
        }

        pruneExpired()
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        items = Self.droppingExpired(from: items)

        if items.count > 500 {
            items = Array(items.prefix(500))
        }

        save()
    }

    /// Most recent entry that matches the query signature exactly, so the
    /// result can be replayed without another API round trip.
    func cachedItem(
        sourceText: String, mode: String, actionID: String?, model: String, targetLang: String
    ) -> HistoryItem? {
        pruneExpired()
        return items.first {
            $0.model == model && $0.mode == mode && $0.actionID == actionID
                && $0.targetLang == targetLang && $0.sourceText == sourceText
        }
    }

    /// Drops entries older than the retention window in settings.
    func pruneExpired() {
        let pruned: [HistoryItem] = Self.droppingExpired(from: items)
        if pruned.count != items.count {
            items = pruned
            save()
        }
    }

    func delete(id: UUID) {
        let originalCount: Int = items.count
        items.removeAll { $0.id == id }

        if items.count != originalCount {
            save()
        }
    }

    func clear() {
        guard !items.isEmpty else { return }

        items.removeAll()
        save()
    }
}

private extension HistoryStore {
    static func droppingExpired(from items: [HistoryItem]) -> [HistoryItem] {
        guard let maxAge: TimeInterval = SettingsStore.shared.settings.historyRetention.maxAge
        else { return items }

        let cutoff: Date = Date(timeIntervalSinceNow: -maxAge)
        return items.filter { $0.date >= cutoff }
    }

    static func makeHistoryFileURL(fileManager: FileManager) -> URL {
        let applicationSupportURL: URL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupportURL
            .appendingPathComponent("com.nexttranslator.native", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    static func loadItems(from url: URL, decoder: JSONDecoder) -> [HistoryItem] {
        do {
            let data: Data = try Data(contentsOf: url)
            return try decoder.decode([HistoryItem].self, from: data)
        } catch {
            printError("HistoryStore failed to load history: \(error)")
            return []
        }
    }

    func save() {
        let snapshot: [HistoryItem] = items
        let historyFileURL: URL = self.historyFileURL

        persistenceQueue.async {
            do {
                let directoryURL: URL = historyFileURL.deletingLastPathComponent()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let data: Data = try encoder.encode(snapshot)

                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try data.write(to: historyFileURL, options: [.atomic])
            } catch {
                Self.printError("HistoryStore failed to save history: \(error)")
            }
        }
    }

    nonisolated static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
