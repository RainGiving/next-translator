import Foundation
import NaturalLanguage

enum TranslateMode: String, CaseIterable, Identifiable {
    case translate
    case polishing
    case summarize
    case analyze
    case explainCode = "explain-code"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .translate:
            return "Translate"
        case .polishing:
            return "Polish"
        case .summarize:
            return "Summarize"
        case .analyze:
            return "Analyze"
        case .explainCode:
            return "Explain Code"
        }
    }
}

struct PromptBuilder {
    static func messages(
        mode: TranslateMode,
        text: String,
        sourceLangCode: String,
        targetLangCode: String
    ) -> [ChatMessage] {
        let sourceLangName: String = languageName(for: sourceLangCode)
        let targetLangName: String = languageName(for: targetLangCode)
        let targetSpec: LanguageSpec = languageSpec(for: targetLangCode)
        let toChinese: Bool = chineseLangCodes.contains(targetLangCode)

        var rolePrompt: String = targetSpec.rolePrompt
        var commandPrompt: String = ""
        var contentPrompt: String = text

        switch mode {
        case .translate:
            commandPrompt = "Please translate to \(targetLangName)"
            contentPrompt = text

            if text.count < 5 && toChinese {
                rolePrompt = shortChinesePhraseRolePrompt(
                    targetLangName: targetLangName,
                    phoneticNotation: targetSpec.phoneticNotation
                )
                commandPrompt = ""
            }

            if isSingleWord(text, languageCode: sourceLangCode) {
                if toChinese {
                    rolePrompt = chineseDictionaryRolePrompt(phoneticNotation: targetSpec.phoneticNotation)
                    commandPrompt = "好的，我明白了，请给我这个单词。"
                    contentPrompt = "单词是：\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
                } else {
                    rolePrompt = englishDictionaryRolePrompt(
                        sourceLangName: sourceLangName,
                        targetLangName: targetLangName,
                        phoneticNotation: targetSpec.phoneticNotation,
                        isSameLanguage: sourceLangCode == targetLangCode
                    )
                    commandPrompt = "I understand. Please give me the word."
                    contentPrompt = "The word is: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            }

        case .polishing:
            rolePrompt = "You are an expert translator, translate directly without explanation."
            commandPrompt = "Please edit the following sentences in \(sourceLangName) to improve clarity, conciseness, and coherence, making them match the expression of native speakers."
            contentPrompt = text

        case .summarize:
            rolePrompt = "You are a professional text summarizer, you can only summarize the text, don't interpret it."
            commandPrompt = "Please summarize this text in the most concise language and must use \(targetLangName) language!"
            contentPrompt = text

        case .analyze:
            rolePrompt = "You are a professional translation engine and grammar analyzer."
            commandPrompt = "Please translate this text to \(targetLangName) and explain the grammar in the original text using \(targetLangName)."
            contentPrompt = text

        case .explainCode:
            rolePrompt = "You are a code explanation engine that can only explain code but not interpret or translate it. Also, please report bugs and errors (if any)."
            commandPrompt = "Explain the provided code, regex or script in the most concise language and must use \(targetLangName) language! You may use Markdown. If the content is not code, return an error message. If the code has obvious errors, point them out."
            contentPrompt = "```\n\(text)\n```"
        }

        if !contentPrompt.isEmpty {
            let trimmedContent: String = contentPrompt.trimmingTrailingWhitespaceAndNewlines()
            if commandPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commandPrompt = "Only reply the result and nothing else.\n\n\(trimmedContent)"
            } else {
                commandPrompt = "Only reply the result and nothing else. \(commandPrompt):\n\n\(trimmedContent)"
            }
        }

        return [
            ChatMessage(role: "system", content: rolePrompt),
            ChatMessage(role: "user", content: commandPrompt),
        ]
    }
}

private extension PromptBuilder {
    struct LanguageSpec {
        let name: String
        let phoneticNotation: String?
        let rolePrompt: String

        init(name: String, phoneticNotation: String? = "transcription", rolePrompt: String = "You are a professional translator.") {
            self.name = name
            self.phoneticNotation = phoneticNotation
            self.rolePrompt = rolePrompt
        }
    }

    static let chineseLangCodes: Set<String> = ["zh-Hans", "zh-Hant"]

    static let languageSpecs: [String: LanguageSpec] = [
        "en": LanguageSpec(name: "English", phoneticNotation: "IPA"),
        "zh-Hans": LanguageSpec(name: "Simplified Chinese", phoneticNotation: "Pinyin"),
        "zh-Hant": LanguageSpec(name: "Traditional Chinese", phoneticNotation: "Bopomofo"),
        "ja": LanguageSpec(name: "Japanese", phoneticNotation: "hiragana"),
        "ko": LanguageSpec(name: "Korean", phoneticNotation: "Revised Romanization"),
        "fr": LanguageSpec(name: "French", phoneticNotation: "IPA"),
        "de": LanguageSpec(name: "German", phoneticNotation: "IPA"),
        "es": LanguageSpec(name: "Spanish", phoneticNotation: "IPA"),
        "ru": LanguageSpec(name: "Russian", phoneticNotation: "Latin transcription"),
        "it": LanguageSpec(name: "Italian", phoneticNotation: "IPA"),
        "pt": LanguageSpec(name: "Portuguese"),
        "th": LanguageSpec(name: "Thai", phoneticNotation: "IPA"),
        "ar": LanguageSpec(name: "Arabic", phoneticNotation: "Arabic script"),
        "hi": LanguageSpec(name: "Hindi", phoneticNotation: "latin transcription"),
        "vi": LanguageSpec(name: "Vietnamese", phoneticNotation: nil),
    ]

    static func languageSpec(for code: String) -> LanguageSpec {
        languageSpecs[code] ?? LanguageSpec(name: code)
    }

    static func languageName(for code: String) -> String {
        languageSpec(for: code).name
    }

    static func shortChinesePhraseRolePrompt(targetLangName: String, phoneticNotation: String?) -> String {
        let notation: String = phoneticNotation ?? "音标或转写"

        return """
        你是一个翻译引擎，请将给到的文本翻译成\(targetLangName)。
        请列出3种（如果有）最常用翻译结果：单词或短语，并列出对应的适用语境（用中文阐述）、音标或转写、词性、双语示例。
        按照下面格式用中文阐述：

        <序号>. <单词或短语> · /<\(notation)>/
        [<词性缩写>] <适用语境（用中文阐述）>
        例句：<例句>（<例句翻译>）
        """
    }

    static func chineseDictionaryRolePrompt(phoneticNotation: String?) -> String {
        let notationLine: String
        if let phoneticNotation {
            notationLine = "[<语种>] · /<\(phoneticNotation)>/"
        } else {
            notationLine = "[<语种>]"
        }

        return """
        你是一个翻译引擎，请翻译给出的文本，只输出翻译结果。
        当文本只有一个单词时，请给出单词原始形态（如果有）、单词的语种、对应的音标或转写、所有含义（含词性）、双语示例，至少三条例句。
        如果你认为单词拼写错误，请提示最可能的正确拼写。
        请严格按照下面格式给出翻译结果：

        <单词>（<原始形态>）
        \(notationLine)
        [<词性缩写>] <中文含义>
        例句：
        <序号>. <例句>（<例句翻译>）
        词源：
        <词源>
        """
    }

    static func englishDictionaryRolePrompt(
        sourceLangName: String,
        targetLangName: String,
        phoneticNotation: String?,
        isSameLanguage: Bool
    ) -> String {
        let notationClause: String = phoneticNotation.map {
            "the corresponding phonetic notation or transcription (\($0)), "
        } ?? ""
        let notationLine: String = phoneticNotation.map {
            "[<language>] · /<\($0)>/"
        } ?? "[<language>]"
        let translatedMeaningPlaceholder: String = isSameLanguage ? "" : "<translated meaning> / "
        let exampleKind: String = isSameLanguage ? "" : "bilingual "

        return """
        You are a professional translation engine.
        Please translate the text into \(targetLangName) without explanation.
        When the text has only one word, act as a professional \(sourceLangName)-\(targetLangName) dictionary, and list the original form of the word (if any), the language of the word, \(notationClause)all senses with parts of speech, \(exampleKind)sentence examples (at least 3), and etymology.
        If you think there is a spelling mistake, please tell me the most possible correct word.
        Reply in the following format:

        <word> (<original form>)
        \(notationLine)
        [<part of speech>] \(translatedMeaningPlaceholder)<meaning in source language>
        Examples:
        <index>. <sentence>(<sentence translation>)
        Etymology:
        <etymology>
        """
    }

    static func isSingleWord(_ text: String, languageCode: String) -> Bool {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let tokenizer: NLTokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed

        var tokenRange: Range<String.Index>?
        var tokenCount: Int = 0

        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            tokenCount += 1
            if tokenCount == 1 {
                tokenRange = range
            }
            return tokenCount < 2
        }

        if tokenCount == 1, let tokenRange {
            return tokenRange.lowerBound == trimmed.startIndex && tokenRange.upperBound == trimmed.endIndex
        }

        if tokenCount == 0 {
            let separators: CharacterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            return trimmed.rangeOfCharacter(from: separators) == nil
        }

        return false
    }
}

private extension String {
    func trimmingTrailingWhitespaceAndNewlines() -> String {
        var result: String = self

        while let scalar = result.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(scalar) {
            result.removeLast()
        }

        return result
    }
}
