import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared: SettingsStore = SettingsStore()

    @Published var settings: AppSettings

    private let fileManager: FileManager
    private let settingsFileURL: URL
    private let legacyConfigURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.settingsFileURL = Self.makeSettingsFileURL(fileManager: fileManager)
        self.legacyConfigURL = Self.makeLegacyConfigURL(fileManager: fileManager)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if fileManager.fileExists(atPath: settingsFileURL.path) {
            self.settings = (try? Self.loadSettings(from: settingsFileURL, decoder: decoder)) ?? AppSettings()
        } else {
            self.settings = (try? Self.migrateSettings(from: legacyConfigURL, decoder: decoder)) ?? AppSettings()
            try? save()
        }
    }

    func save() throws {
        let directoryURL: URL = settingsFileURL.deletingLastPathComponent()
        let data: Data = try encoder.encode(settings)

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: settingsFileURL, options: [.atomic])
    }

    private static func makeSettingsFileURL(fileManager: FileManager) -> URL {
        let applicationSupportURL: URL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupportURL
            .appendingPathComponent("com.nexttranslator.native", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    private static func makeLegacyConfigURL(fileManager: FileManager) -> URL {
        let applicationSupportURL: URL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupportURL
            .appendingPathComponent("com.nexttranslator.app", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    private static func loadSettings(from url: URL, decoder: JSONDecoder) throws -> AppSettings {
        let data: Data = try Data(contentsOf: url)
        return try decoder.decode(AppSettings.self, from: data)
    }

    private static func migrateSettings(from url: URL, decoder: JSONDecoder) throws -> AppSettings {
        let data: Data = try Data(contentsOf: url)
        let legacySettings: LegacySettings = try decoder.decode(LegacySettings.self, from: data)

        return AppSettings(
            apiKey: legacySettings.primaryAPIKey ?? "",
            apiBaseURL: legacySettings.apiURL ?? "https://api.openai.com",
            apiModel: legacySettings.apiModel ?? "gpt-4o-mini",
            defaultMode: migratedDefaultMode(from: legacySettings.defaultTranslateMode),
            targetLanguage: legacySettings.defaultTargetLanguage ?? "zh-Hans",
            secondaryTargetLanguage: "en"
        )
    }

    private static func migratedDefaultMode(from legacyMode: String?) -> String {
        guard let legacyMode, TranslateMode(rawValue: legacyMode) != nil else {
            return TranslateMode.translate.rawValue
        }

        return legacyMode
    }

    private struct LegacySettings: Decodable {
        let apiKeys: String?
        let apiURL: String?
        let apiModel: String?
        let defaultTranslateMode: String?
        let defaultTargetLanguage: String?

        var primaryAPIKey: String? {
            guard let apiKeys: String else { return nil }

            let key: String = apiKeys
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""

            return key.isEmpty ? nil : key
        }
    }
}
