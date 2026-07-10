import Foundation

enum HistoryRetention: String, CaseIterable, Identifiable {
    case day = "24h"
    case week = "7d"
    case month = "1m"
    case quarter = "3m"
    case year = "1y"
    case forever

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return String(localized: "24 hours")
        case .week: return String(localized: "7 days")
        case .month: return String(localized: "1 month")
        case .quarter: return String(localized: "3 months")
        case .year: return String(localized: "1 year")
        case .forever: return String(localized: "Forever")
        }
    }

    /// Oldest allowed entry age; nil keeps history indefinitely.
    var maxAge: TimeInterval? {
        switch self {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .quarter: return 90 * 24 * 3600
        case .year: return 365 * 24 * 3600
        case .forever: return nil
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// Concrete languages are named in themselves so they stay recognisable
    /// from any current interface language.
    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    /// Points the per-app AppleLanguages override at the chosen language.
    /// Takes effect on the next launch.
    func applyOverride() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        default:
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// A connection profile for one OpenAI-compatible endpoint. Preset providers
/// pin their base URL; custom providers are fully editable and deletable.
struct APIProvider: Codable, Identifiable, Hashable {
    var id: UUID
    /// Preset key ("openai", "deepseek", …); nil for user-created providers.
    var preset: String?
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String

    var isPreset: Bool { preset != nil }
}

enum ProviderPreset: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case deepSeek = "deepseek"
    case moonshot
    case groq
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .moonshot: return "Moonshot"
        case .groq: return "Groq"
        case .ollama: return "Ollama"
        }
    }

    var baseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com"
        case .deepSeek: return "https://api.deepseek.com"
        case .moonshot: return "https://api.moonshot.cn"
        case .groq: return "https://api.groq.com/openai"
        case .ollama: return "http://127.0.0.1:11434/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .deepSeek: return "deepseek-chat"
        case .moonshot: return "kimi-k2-0711-preview"
        case .groq: return "llama-3.3-70b-versatile"
        case .ollama: return ""
        }
    }

    func provider() -> APIProvider {
        APIProvider(
            id: UUID(), preset: rawValue, name: displayName,
            baseURL: baseURL, apiKey: "", model: defaultModel)
    }
}

struct AppSettings: Codable {
    var providers: [APIProvider]
    var activeProviderID: UUID
    /// True when this value was decoded from the pre-profile flat format;
    /// signals the store to rewrite the file so provider IDs stabilise.
    var decodedFromLegacyFormat: Bool = false
    var defaultMode: String
    var targetLanguage: String
    var secondaryTargetLanguage: String
    var historyRetention: HistoryRetention
    var appLanguage: AppLanguage
    var pinned: Bool
    var hideOnFocusLoss: Bool
    /// Share of the space between the header and footer given to the input
    /// editor; the divider between the two cards drags it.
    var editorSplitFraction: Double
    var showWindowKeyCode: UInt32
    var showWindowModifiers: UInt32
    var selectionKeyCode: UInt32
    var selectionModifiers: UInt32

    var activeProvider: APIProvider {
        providers.first { $0.id == activeProviderID }
            ?? providers.first
            ?? ProviderPreset.openAI.provider()
    }

    private var activeProviderIndex: Int? {
        providers.firstIndex { $0.id == activeProviderID }
            ?? (providers.isEmpty ? nil : 0)
    }

    /// Flat accessors kept for the call sites that predate provider profiles;
    /// they read from and write through to the active provider.
    var apiKey: String {
        get { activeProvider.apiKey }
        set { if let index = activeProviderIndex { providers[index].apiKey = newValue } }
    }

    var apiBaseURL: String {
        get { activeProvider.baseURL }
        set { if let index = activeProviderIndex { providers[index].baseURL = newValue } }
    }

    var apiModel: String {
        get { activeProvider.model }
        set { if let index = activeProviderIndex { providers[index].model = newValue } }
    }

    init(
        apiKey: String = "",
        apiBaseURL: String = "https://api.openai.com",
        apiModel: String = "gpt-4o-mini",
        defaultMode: String = "translate",
        targetLanguage: String = "zh-Hans",
        secondaryTargetLanguage: String = "en",
        historyRetention: HistoryRetention = .forever,
        appLanguage: AppLanguage = .system,
        pinned: Bool = false,
        hideOnFocusLoss: Bool = true,
        editorSplitFraction: Double = 0.44,
        showWindowKeyCode: UInt32 = 17,
        showWindowModifiers: UInt32 = 2304,
        selectionKeyCode: UInt32 = 2,
        selectionModifiers: UInt32 = 2304
    ) {
        (self.providers, self.activeProviderID) = Self.providersFromFlat(
            apiKey: apiKey, baseURL: apiBaseURL, model: apiModel)
        self.defaultMode = defaultMode
        self.targetLanguage = targetLanguage
        self.secondaryTargetLanguage = secondaryTargetLanguage
        self.historyRetention = historyRetention
        self.appLanguage = appLanguage
        self.pinned = pinned
        self.hideOnFocusLoss = hideOnFocusLoss
        self.editorSplitFraction = editorSplitFraction
        self.showWindowKeyCode = showWindowKeyCode
        self.showWindowModifiers = showWindowModifiers
        self.selectionKeyCode = selectionKeyCode
        self.selectionModifiers = selectionModifiers
    }

    /// Seeds the preset providers and routes flat key/URL/model values into a
    /// matching preset, or into a custom provider when no preset fits.
    private static func providersFromFlat(
        apiKey: String, baseURL: String, model: String
    ) -> ([APIProvider], UUID) {
        var providers: [APIProvider] = ProviderPreset.allCases.map { $0.provider() }
        let trimmedBaseURL: String = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = providers.firstIndex(where: { $0.baseURL == trimmedBaseURL }) {
            providers[index].apiKey = apiKey
            if !model.isEmpty {
                providers[index].model = model
            }
            return (providers, providers[index].id)
        }

        let custom: APIProvider = APIProvider(
            id: UUID(), preset: nil, name: String(localized: "Custom"),
            baseURL: trimmedBaseURL, apiKey: apiKey, model: model)
        providers.append(custom)
        return (providers, custom.id)
    }

    /// Re-adds any preset missing from a stored providers array (new presets
    /// shipped in updates) while keeping stored keys and custom providers.
    private static func ensuringPresets(_ stored: [APIProvider]) -> [APIProvider] {
        let presentPresets: Set<String> = Set(stored.compactMap(\.preset))
        var providers: [APIProvider] = stored

        for preset: ProviderPreset in ProviderPreset.allCases
        where !presentPresets.contains(preset.rawValue) {
            providers.append(preset.provider())
        }

        return providers
    }

    private enum CodingKeys: String, CodingKey {
        case providers
        case activeProviderID
        case apiKey
        case apiBaseURL
        case apiModel
        case defaultMode
        case targetLanguage
        case secondaryTargetLanguage
        case historyRetention
        case appLanguage
        case pinned
        case hideOnFocusLoss
        case editorSplitFraction
        case showWindowKeyCode
        case showWindowModifiers
        case selectionKeyCode
        case selectionModifiers
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        if let storedProviders = try container.decodeIfPresent([APIProvider].self, forKey: .providers),
            !storedProviders.isEmpty
        {
            let providers: [APIProvider] = Self.ensuringPresets(storedProviders)
            let storedActiveID: UUID? = try container.decodeIfPresent(UUID.self, forKey: .activeProviderID)
            self.providers = providers
            self.activeProviderID =
                providers.first(where: { $0.id == storedActiveID })?.id ?? providers[0].id
        } else {
            // Pre-profile settings carried one flat key/URL/model triple.
            (self.providers, self.activeProviderID) = Self.providersFromFlat(
                apiKey: try container.decodeIfPresent(String.self, forKey: .apiKey) ?? "",
                baseURL: try container.decodeIfPresent(String.self, forKey: .apiBaseURL)
                    ?? "https://api.openai.com",
                model: try container.decodeIfPresent(String.self, forKey: .apiModel) ?? "gpt-4o-mini")
            self.decodedFromLegacyFormat = true
        }
        self.defaultMode = try container.decodeIfPresent(String.self, forKey: .defaultMode) ?? "translate"
        self.targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
        self.secondaryTargetLanguage = try container.decodeIfPresent(String.self, forKey: .secondaryTargetLanguage) ?? "en"
        self.historyRetention = HistoryRetention(
            rawValue: try container.decodeIfPresent(String.self, forKey: .historyRetention) ?? ""
        ) ?? .forever
        self.appLanguage = AppLanguage(
            rawValue: try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? ""
        ) ?? .system
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.hideOnFocusLoss = try container.decodeIfPresent(Bool.self, forKey: .hideOnFocusLoss) ?? true
        self.editorSplitFraction = min(
            max(try container.decodeIfPresent(Double.self, forKey: .editorSplitFraction) ?? 0.44, 0.1),
            0.9)
        self.showWindowKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .showWindowKeyCode) ?? 17
        self.showWindowModifiers = try container.decodeIfPresent(UInt32.self, forKey: .showWindowModifiers) ?? 2304
        self.selectionKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .selectionKeyCode) ?? 2
        self.selectionModifiers = try container.decodeIfPresent(UInt32.self, forKey: .selectionModifiers) ?? 2304
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(providers, forKey: .providers)
        try container.encode(activeProviderID, forKey: .activeProviderID)
        try container.encode(defaultMode, forKey: .defaultMode)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        try container.encode(secondaryTargetLanguage, forKey: .secondaryTargetLanguage)
        try container.encode(historyRetention.rawValue, forKey: .historyRetention)
        try container.encode(appLanguage.rawValue, forKey: .appLanguage)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(hideOnFocusLoss, forKey: .hideOnFocusLoss)
        try container.encode(editorSplitFraction, forKey: .editorSplitFraction)
        try container.encode(showWindowKeyCode, forKey: .showWindowKeyCode)
        try container.encode(showWindowModifiers, forKey: .showWindowModifiers)
        try container.encode(selectionKeyCode, forKey: .selectionKeyCode)
        try container.encode(selectionModifiers, forKey: .selectionModifiers)
    }
}
