import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Application-wide state and service wiring. Owns the current query, the
/// streaming translation, window behaviour and the PopClip IPC lifecycle.
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
    @Published var isPinned: Bool
    @Published var availableModels: [String] = []
    @Published var isLoadingModels: Bool = false
    @Published var modelsError: String?

    private var ipcServer: IPCServer?
    private var currentTask: Task<Void, Never>?
    /// Bumped whenever the current translation becomes obsolete (new query,
    /// restore, stop). Callbacks from superseded tasks compare against it and
    /// drop out instead of clobbering newer state.
    private var translationGeneration: UInt64 = 0
    private var modelsGeneration: UInt64 = 0
    private var settingsObserver: AnyCancellable?
    private var registeredHotkeys: [UInt32]?

    private init() {
        let settings = SettingsStore.shared.settings
        isPinned = settings.pinned
        let actions = ActionStore.shared.actions
        currentAction =
            actions.first(where: { ($0.builtinMode ?? $0.id.uuidString) == settings.defaultMode })
            ?? actions.first
            ?? TranslatorAction(
                id: UUID(), name: "Translate", icon: "translate",
                builtinMode: TranslateMode.translate.rawValue, rolePrompt: "", commandPrompt: "")
    }

    // MARK: services

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

        applyHotkeys(from: SettingsStore.shared.settings)
        settingsObserver = SettingsStore.shared.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.applyHotkeys(from: settings)
            }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self,
                    let window = note.object as? NSWindow,
                    window.identifier?.rawValue.contains("translator") == true,
                    !self.isPinned,
                    SettingsStore.shared.settings.hideOnFocusLoss
                else { return }
                window.orderOut(nil)
            }
        }
    }

    /// (Re)binds the two global hotkeys from settings; hot-reloads on change.
    private func applyHotkeys(from settings: AppSettings) {
        let combo = [
            settings.showWindowKeyCode, settings.showWindowModifiers,
            settings.selectionKeyCode, settings.selectionModifiers,
        ]
        if registeredHotkeys == combo {
            return
        }
        registeredHotkeys = combo
        HotkeyManager.shared.unregisterAll()
        HotkeyManager.shared.register(
            HotkeySpec(keyCode: combo[0], carbonModifiers: combo[1])
        ) { [weak self] in
            self?.showTranslatorWindow()
        }
        HotkeyManager.shared.register(
            HotkeySpec(keyCode: combo[2], carbonModifiers: combo[3])
        ) { [weak self] in
            guard SelectionReader.ensureAccessibilityPermission(prompt: true) else { return }
            Task { @MainActor in
                if let text = await SelectionReader.readSelectedText(), !text.isEmpty {
                    self?.handleIncomingText(text)
                }
            }
        }
    }

    // MARK: translation

    func handleIncomingText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = trimmed
        querySeq &+= 1
        showTranslatorWindow()
        translate()
    }

    /// Marks any in-flight translation as obsolete.
    private func invalidateTranslation() {
        currentTask?.cancel()
        translationGeneration &+= 1
    }

    func stopTranslation() {
        invalidateTranslation()
        isTranslating = false
    }

    func translate() {
        invalidateTranslation()
        let generation = translationGeneration
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let settings = SettingsStore.shared.settings
        guard Self.hasUsableCredentials(settings), let baseURL = URL(string: settings.apiBaseURL) else {
            errorMessage = String(localized: "Set your API key in Settings first.")
            return
        }

        let sourceLang = LangDetector.detect(text)
        // Compare base languages so zh-Hans/zh-Hant misdetection on short
        // text can't trigger a pointless Chinese-to-Chinese translation.
        let targetLang =
            Self.baseLanguage(sourceLang) == Self.baseLanguage(settings.targetLanguage)
            ? settings.secondaryTargetLanguage : settings.targetLanguage
        lastSourceLang = sourceLang
        lastTargetLang = targetLang

        let action = currentAction
        // Built-in actions whose prompts are untouched (or blank) keep the
        // smart prompt assembly; edited templates are honoured as-is.
        let usesSmartPrompts: Bool = {
            guard let raw = action.builtinMode,
                let canonical = ActionStore.canonicalBuiltin(mode: raw)
            else { return false }
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
                if (error as? URLError)?.code == .cancelled {
                    return
                }
                if isCurrent() {
                    self?.errorMessage = error.localizedDescription
                }
            }
            if isCurrent() {
                self?.isTranslating = false
            }
        }
    }

    /// Local endpoints (Ollama & friends) work without an API key.
    private static func hasUsableCredentials(_ settings: AppSettings) -> Bool {
        if !settings.apiKey.isEmpty {
            return true
        }
        let host = URL(string: settings.apiBaseURL)?.host ?? ""
        return host == "127.0.0.1" || host == "localhost" || host.hasSuffix(".local")
    }

    private static func baseLanguage(_ code: String) -> String {
        code.hasPrefix("zh") ? "zh" : String(code.prefix(2))
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

    // MARK: model list

    func refreshModels() {
        let settings = SettingsStore.shared.settings
        guard Self.hasUsableCredentials(settings), let baseURL = URL(string: settings.apiBaseURL) else {
            modelsError = String(localized: "Set your API key in Settings first.")
            return
        }
        modelsGeneration &+= 1
        let generation = modelsGeneration
        isLoadingModels = true
        modelsError = nil
        let client = OpenAIClient(baseURL: baseURL, apiKey: settings.apiKey, model: settings.apiModel)
        Task { [weak self] in
            do {
                let models = try await client.listModels()
                guard self?.modelsGeneration == generation else { return }
                self?.availableModels = models
            } catch {
                guard self?.modelsGeneration == generation else { return }
                self?.modelsError = error.localizedDescription
            }
            if self?.modelsGeneration == generation {
                self?.isLoadingModels = false
            }
        }
    }

    func selectModel(_ model: String) {
        SettingsStore.shared.settings.apiModel = model
        try? SettingsStore.shared.save()
    }

    // MARK: history

    /// Restore a history entry into the window without re-translating.
    func restore(_ item: HistoryItem) {
        invalidateTranslation()
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

    // MARK: window behaviour

    func toggleAlwaysOnTop() {
        isPinned.toggle()
        SettingsStore.shared.settings.pinned = isPinned
        try? SettingsStore.shared.save()
        applyWindowTraits()
    }

    /// Applies pin level and space behaviour; safe to call repeatedly.
    func applyWindowTraits() {
        guard let window = translatorWindow else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.level = isPinned ? .floating : .normal
    }

    func showTranslatorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = translatorWindow else { return }
        applyWindowTraits()
        moveToMouseScreen(window)
        window.makeKeyAndOrderFront(nil)
    }

    func hideTranslatorWindow() {
        translatorWindow?.orderOut(nil)
    }

    /// PopClip and hotkeys can fire on any display; bring the window to the
    /// screen the mouse is on instead of yanking the user across spaces.
    private func moveToMouseScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let target = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
            window.screen !== target
        else { return }
        let size = window.frame.size
        let visible = target.visibleFrame
        window.setFrame(
            NSRect(
                x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                width: size.width, height: size.height),
            display: true)
    }

    private var translatorWindow: NSWindow? {
        NSApp.windows.first(where: { $0.identifier?.rawValue.contains("translator") == true })
    }
}
