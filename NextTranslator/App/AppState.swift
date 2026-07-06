import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Application-wide state and service wiring. Owns the current query, the
/// streaming translation, and the PopClip IPC lifecycle.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Production socket: the PopClip extension posts selected text here.
    static let socketPath = "/tmp/next-translator.sock"

    @Published var inputText: String = ""
    /// Bumped on every external hand-off (PopClip / hotkey) so views can
    /// refresh even when the text itself is unchanged.
    @Published var querySeq: UInt64 = 0
    @Published var currentAction: TranslatorAction
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    @Published var lastSourceLang: String = ""
    @Published var lastTargetLang: String = ""
    @Published var isPinned: Bool = false
    @Published var availableModels: [String] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelsError: String?

    private var ipcServer: IPCServer?
    private var currentTask: Task<Void, Never>?
    /// Bumped on every translate() call. Streaming callbacks from a superseded
    /// task compare against it and drop out instead of clobbering the state
    /// of the newer run (rapid action switching used to look unresponsive
    /// because the cancelled task's cleanup reset isTranslating).
    private var translationGeneration: UInt64 = 0

    private init() {
        let actions = ActionStore.shared.actions
        let defaultMode = SettingsStore.shared.settings.defaultMode
        currentAction =
            actions.first(where: { $0.builtinMode == defaultMode })
            ?? actions.first
            ?? TranslatorAction(
                id: UUID(), name: "Translate", icon: "translate",
                builtinMode: TranslateMode.translate.rawValue, rolePrompt: "", commandPrompt: "")
    }

    func startServices() {
        let server = IPCServer(socketPath: Self.socketPath) { [weak self] text in
            self?.handleIncomingText(text)
        }
        do {
            try server.start()
        } catch {
            NSLog("IPC server failed to start: \(error)")
        }
        ipcServer = server
        registerHotkeys()
    }

    private func registerHotkeys() {
        // ⌥⌘T — show the translator window.
        HotkeyManager.shared.register(
            HotkeySpec(keyCode: UInt32(kVK_ANSI_T), carbonModifiers: UInt32(cmdKey | optionKey))
        ) { [weak self] in
            self?.showTranslatorWindow()
        }
        // ⌥⌘D — translate the selection in whatever app is frontmost.
        HotkeyManager.shared.register(
            HotkeySpec(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(cmdKey | optionKey))
        ) { [weak self] in
            guard SelectionReader.ensureAccessibilityPermission(prompt: true) else { return }
            Task { @MainActor in
                if let text = await SelectionReader.readSelectedText(), !text.isEmpty {
                    self?.handleIncomingText(text)
                }
            }
        }
    }

    /// Hand a new text to the translator, bring the window up and start
    /// translating immediately — no clicks needed.
    func handleIncomingText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = trimmed
        querySeq &+= 1
        showTranslatorWindow()
        translate()
    }

    func translate() {
        currentTask?.cancel()
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let settings = SettingsStore.shared.settings
        guard !settings.apiKey.isEmpty, let baseURL = URL(string: settings.apiBaseURL) else {
            errorMessage = String(localized: "Set your API key in Settings first.")
            return
        }

        let sourceLang = LangDetector.detect(text)
        let targetLang =
            sourceLang == settings.targetLanguage
            ? settings.secondaryTargetLanguage : settings.targetLanguage
        lastSourceLang = sourceLang
        lastTargetLang = targetLang

        let action = currentAction
        // Built-in actions whose prompts are untouched keep the smart prompt
        // assembly (dictionary mode for single words, language-aware role
        // prompts). Once the user edits the templates, we honour them as-is.
        let usesSmartPrompts: Bool = {
            guard let raw = action.builtinMode,
                let canonical = ActionStore.canonicalBuiltin(mode: raw)
            else { return false }
            // Blank prompts on a built-in also mean "use the smart built-in
            // logic" (the settings editor documents them that way).
            if action.rolePrompt.isEmpty && action.commandPrompt.isEmpty { return true }
            return action.rolePrompt == canonical.rolePrompt
                && action.commandPrompt == canonical.commandPrompt
        }()
        let messages: [ChatMessage]
        if usesSmartPrompts, let raw = action.builtinMode, let builtinMode = TranslateMode(rawValue: raw) {
            messages = PromptBuilder.messages(
                mode: builtinMode, text: text, sourceLangCode: sourceLang, targetLangCode: targetLang)
        } else {
            messages = Self.customActionMessages(
                action: action, text: text, sourceLang: sourceLang, targetLang: targetLang)
        }

        translatedText = ""
        errorMessage = nil
        isTranslating = true
        translationGeneration &+= 1
        let generation = translationGeneration

        let client = OpenAIClient(baseURL: baseURL, apiKey: settings.apiKey, model: settings.apiModel)
        currentTask = Task { [weak self] in
            let isCurrent = { @MainActor in self?.translationGeneration == generation }
            do {
                try await client.streamChat(messages: messages) { delta in
                    guard isCurrent() else { return }
                    self?.translatedText += delta
                }
                if let self, isCurrent(), !self.translatedText.isEmpty {
                    HistoryStore.shared.add(
                        HistoryItem(
                            id: UUID(), date: Date(), mode: action.builtinMode ?? action.name,
                            sourceText: text, translatedText: self.translatedText,
                            sourceLang: sourceLang, targetLang: targetLang))
                }
            } catch is CancellationError {
                return
            } catch {
                if isCurrent() {
                    self?.errorMessage = error.localizedDescription
                }
            }
            if isCurrent() {
                self?.isTranslating = false
            }
        }
    }

    // MARK: model list

    func refreshModels() {
        let settings = SettingsStore.shared.settings
        guard !settings.apiKey.isEmpty || settings.apiBaseURL.contains("127.0.0.1"),
            let baseURL = URL(string: settings.apiBaseURL)
        else {
            modelsError = String(localized: "Set your API key in Settings first.")
            return
        }
        isLoadingModels = true
        modelsError = nil
        let client = OpenAIClient(baseURL: baseURL, apiKey: settings.apiKey, model: settings.apiModel)
        Task { [weak self] in
            do {
                let models = try await client.listModels()
                self?.availableModels = models
            } catch {
                self?.modelsError = error.localizedDescription
            }
            self?.isLoadingModels = false
        }
    }

    func selectModel(_ model: String) {
        SettingsStore.shared.settings.apiModel = model
        try? SettingsStore.shared.save()
    }

    /// Build messages for a user-defined action. Prompts may reference
    /// ${text}, ${sourceLang} and ${targetLang}.
    private static func customActionMessages(
        action: TranslatorAction, text: String, sourceLang: String, targetLang: String
    ) -> [ChatMessage] {
        let english = Locale(identifier: "en")
        let substitute: (String) -> String = { template in
            template
                .replacingOccurrences(
                    of: "${sourceLang}",
                    with: english.localizedString(forIdentifier: sourceLang) ?? sourceLang)
                .replacingOccurrences(
                    of: "${targetLang}",
                    with: english.localizedString(forIdentifier: targetLang) ?? targetLang)
                .replacingOccurrences(of: "${text}", with: text)
        }
        let role = action.rolePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = action.commandPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = role.isEmpty ? "You are a helpful assistant." : substitute(role)
        let user: String
        if command.isEmpty {
            user = text
        } else if command.contains("${text}") {
            user = substitute(command)
        } else {
            user = substitute(command) + "\n\n" + text
        }
        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: user),
        ]
    }

    /// Restore a history entry into the window without re-translating.
    func restore(_ item: HistoryItem) {
        currentTask?.cancel()
        isTranslating = false
        errorMessage = nil
        inputText = item.sourceText
        translatedText = item.translatedText
        if let matched = ActionStore.shared.actions.first(where: {
            ($0.builtinMode ?? $0.name) == item.mode
        }) {
            currentAction = matched
        }
        querySeq &+= 1
    }

    func toggleAlwaysOnTop() {
        isPinned.toggle()
        if let window = translatorWindow {
            window.level = isPinned ? .floating : .normal
        }
    }

    func showTranslatorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = translatorWindow {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var translatorWindow: NSWindow? {
        NSApp.windows.first(where: { $0.identifier?.rawValue.contains("translator") == true })
    }
}
