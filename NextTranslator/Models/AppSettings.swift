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

struct AppSettings: Codable {
    var apiKey: String
    var apiBaseURL: String
    var apiModel: String
    var defaultMode: String
    var targetLanguage: String
    var secondaryTargetLanguage: String
    var historyRetention: HistoryRetention
    var pinned: Bool
    var hideOnFocusLoss: Bool
    var showWindowKeyCode: UInt32
    var showWindowModifiers: UInt32
    var selectionKeyCode: UInt32
    var selectionModifiers: UInt32

    init(
        apiKey: String = "",
        apiBaseURL: String = "https://api.openai.com",
        apiModel: String = "gpt-4o-mini",
        defaultMode: String = "translate",
        targetLanguage: String = "zh-Hans",
        secondaryTargetLanguage: String = "en",
        historyRetention: HistoryRetention = .forever,
        pinned: Bool = false,
        hideOnFocusLoss: Bool = true,
        showWindowKeyCode: UInt32 = 17,
        showWindowModifiers: UInt32 = 2304,
        selectionKeyCode: UInt32 = 2,
        selectionModifiers: UInt32 = 2304
    ) {
        self.apiKey = apiKey
        self.apiBaseURL = apiBaseURL
        self.apiModel = apiModel
        self.defaultMode = defaultMode
        self.targetLanguage = targetLanguage
        self.secondaryTargetLanguage = secondaryTargetLanguage
        self.historyRetention = historyRetention
        self.pinned = pinned
        self.hideOnFocusLoss = hideOnFocusLoss
        self.showWindowKeyCode = showWindowKeyCode
        self.showWindowModifiers = showWindowModifiers
        self.selectionKeyCode = selectionKeyCode
        self.selectionModifiers = selectionModifiers
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case apiBaseURL
        case apiModel
        case defaultMode
        case targetLanguage
        case secondaryTargetLanguage
        case historyRetention
        case pinned
        case hideOnFocusLoss
        case showWindowKeyCode
        case showWindowModifiers
        case selectionKeyCode
        case selectionModifiers
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? "https://api.openai.com"
        self.apiModel = try container.decodeIfPresent(String.self, forKey: .apiModel) ?? "gpt-4o-mini"
        self.defaultMode = try container.decodeIfPresent(String.self, forKey: .defaultMode) ?? "translate"
        self.targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
        self.secondaryTargetLanguage = try container.decodeIfPresent(String.self, forKey: .secondaryTargetLanguage) ?? "en"
        self.historyRetention = HistoryRetention(
            rawValue: try container.decodeIfPresent(String.self, forKey: .historyRetention) ?? ""
        ) ?? .forever
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.hideOnFocusLoss = try container.decodeIfPresent(Bool.self, forKey: .hideOnFocusLoss) ?? true
        self.showWindowKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .showWindowKeyCode) ?? 17
        self.showWindowModifiers = try container.decodeIfPresent(UInt32.self, forKey: .showWindowModifiers) ?? 2304
        self.selectionKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .selectionKeyCode) ?? 2
        self.selectionModifiers = try container.decodeIfPresent(UInt32.self, forKey: .selectionModifiers) ?? 2304
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(apiBaseURL, forKey: .apiBaseURL)
        try container.encode(apiModel, forKey: .apiModel)
        try container.encode(defaultMode, forKey: .defaultMode)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        try container.encode(secondaryTargetLanguage, forKey: .secondaryTargetLanguage)
        try container.encode(historyRetention.rawValue, forKey: .historyRetention)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(hideOnFocusLoss, forKey: .hideOnFocusLoss)
        try container.encode(showWindowKeyCode, forKey: .showWindowKeyCode)
        try container.encode(showWindowModifiers, forKey: .showWindowModifiers)
        try container.encode(selectionKeyCode, forKey: .selectionKeyCode)
        try container.encode(selectionModifiers, forKey: .selectionModifiers)
    }
}
