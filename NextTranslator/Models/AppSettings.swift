import Foundation

struct AppSettings: Codable {
    var apiKey: String
    var apiBaseURL: String
    var apiModel: String
    var targetLanguage: String
    var secondaryTargetLanguage: String

    init(
        apiKey: String = "",
        apiBaseURL: String = "https://api.openai.com",
        apiModel: String = "gpt-4o-mini",
        targetLanguage: String = "zh-Hans",
        secondaryTargetLanguage: String = "en"
    ) {
        self.apiKey = apiKey
        self.apiBaseURL = apiBaseURL
        self.apiModel = apiModel
        self.targetLanguage = targetLanguage
        self.secondaryTargetLanguage = secondaryTargetLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case apiBaseURL
        case apiModel
        case targetLanguage
        case secondaryTargetLanguage
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? "https://api.openai.com"
        self.apiModel = try container.decodeIfPresent(String.self, forKey: .apiModel) ?? "gpt-4o-mini"
        self.targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
        self.secondaryTargetLanguage = try container.decodeIfPresent(String.self, forKey: .secondaryTargetLanguage) ?? "en"
    }
}
