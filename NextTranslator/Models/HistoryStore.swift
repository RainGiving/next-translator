import Combine
import Foundation

struct HistoryItem: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let mode: String
    let sourceText: String
    let translatedText: String
    let sourceLang: String
    let targetLang: String
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem]

    private let fileManager: FileManager
    private let historyFileURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.historyFileURL = Self.makeHistoryFileURL(fileManager: fileManager)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if fileManager.fileExists(atPath: historyFileURL.path) {
            self.items = Self.loadItems(from: historyFileURL, decoder: decoder)
        } else {
            self.items = []
        }
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)

        if items.count > 500 {
            items = Array(items.prefix(500))
        }

        save()
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
        do {
            let directoryURL: URL = historyFileURL.deletingLastPathComponent()
            let data: Data = try encoder.encode(items)

            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: historyFileURL, options: [.atomic])
        } catch {
            Self.printError("HistoryStore failed to save history: \(error)")
        }
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
