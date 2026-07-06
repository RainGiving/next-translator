import Foundation

struct AppSettings: Codable {
    var apiKey: String
    var apiBaseURL: String
    var apiModel: String
    var defaultMode: String
    var targetLanguage: String
    var secondaryTargetLanguage: String

    init(
        apiKey: String = "",
        apiBaseURL: String = "https://api.openai.com",
        apiModel: String = "gpt-4o-mini",
        defaultMode: String = "translate",
        targetLanguage: String = "zh-Hans",
        secondaryTargetLanguage: String = "en"
    ) {
        self.apiKey = apiKey
        self.apiBaseURL = apiBaseURL
        self.apiModel = apiModel
        self.defaultMode = Self.normalizedDefaultMode(defaultMode)
        self.targetLanguage = targetLanguage
        self.secondaryTargetLanguage = secondaryTargetLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case apiBaseURL
        case apiModel
        case defaultMode
        case targetLanguage
        case secondaryTargetLanguage
    }

    private static let fallbackDefaultMode: String = "translate"
    private static let allowedDefaultModes: Set<String> = [
        "translate", "polishing", "summarize", "analyze", "explain-code",
    ]

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? "https://api.openai.com"
        self.apiModel = try container.decodeIfPresent(String.self, forKey: .apiModel) ?? "gpt-4o-mini"
        self.defaultMode = Self.normalizedDefaultMode(try container.decodeIfPresent(String.self, forKey: .defaultMode))
        self.targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
        self.secondaryTargetLanguage = try container.decodeIfPresent(String.self, forKey: .secondaryTargetLanguage) ?? "en"
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(apiBaseURL, forKey: .apiBaseURL)
        try container.encode(apiModel, forKey: .apiModel)
        try container.encode(defaultMode, forKey: .defaultMode)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        try container.encode(secondaryTargetLanguage, forKey: .secondaryTargetLanguage)
    }

    private static func normalizedDefaultMode(_ value: String?) -> String {
        guard let value, allowedDefaultModes.contains(value) else {
            return fallbackDefaultMode
        }

        return value
    }
}
