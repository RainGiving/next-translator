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

        let initialSettings: AppSettings
        let shouldSaveSettings: Bool
        if fileManager.fileExists(atPath: settingsFileURL.path) {
            do {
                initialSettings = try Self.loadSettings(from: settingsFileURL, decoder: decoder)
                shouldSaveSettings = false
            } catch {
                Self.printError("SettingsStore failed to decode settings.json: \(error)")
                let backupSucceeded: Bool = Self.backUpInvalidSettings(at: settingsFileURL, fileManager: fileManager)
                initialSettings = AppSettings()
                shouldSaveSettings = backupSucceeded
            }
        } else {
            initialSettings = (try? Self.migrateSettings(from: legacyConfigURL, decoder: decoder)) ?? AppSettings()
            shouldSaveSettings = true
        }

        self.settings = initialSettings

        if shouldSaveSettings {
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
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: settingsFileURL.path
        )
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

    private static func backUpInvalidSettings(at url: URL, fileManager: FileManager) -> Bool {
        let backupURL: URL = url
            .deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).bak", isDirectory: false)

        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: url, to: backupURL)
            Self.printError("SettingsStore moved invalid settings.json to \(backupURL.path)")
            return true
        } catch {
            Self.printError("SettingsStore failed to back up invalid settings.json: \(error)")
            return false
        }
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

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
