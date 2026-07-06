import NaturalLanguage

enum LangDetector {
    static func detect(_ text: String) -> String {
        let trimmedText: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "en" }

        let recognizer: NLLanguageRecognizer = NLLanguageRecognizer()
        recognizer.processString(trimmedText)

        guard let language: NLLanguage = recognizer.dominantLanguage else {
            return "en"
        }

        return language.rawValue
    }
}
