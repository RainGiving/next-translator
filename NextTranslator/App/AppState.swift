import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Application-wide state and service wiring. Owns the current query, the
/// streaming translation, and the PopClip IPC lifecycle.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Dev socket path; switches to /tmp/next-translator.sock when the native
    /// app replaces the Tauri build so the PopClip extension keeps working.
    static let socketPath = "/tmp/next-translator-native.sock"

    @Published var inputText: String = ""
    /// Bumped on every external hand-off (PopClip / hotkey) so views can
    /// refresh even when the text itself is unchanged.
    @Published var querySeq: UInt64 = 0
    @Published var mode: TranslateMode = .translate
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?

    private var ipcServer: IPCServer?
    private var currentTask: Task<Void, Never>?

    private init() {}

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
        let messages = PromptBuilder.messages(
            mode: mode, text: text, sourceLangCode: sourceLang, targetLangCode: targetLang)

        translatedText = ""
        errorMessage = nil
        isTranslating = true

        let client = OpenAIClient(baseURL: baseURL, apiKey: settings.apiKey, model: settings.apiModel)
        let queryMode = mode
        currentTask = Task { [weak self] in
            do {
                try await client.streamChat(messages: messages) { delta in
                    self?.translatedText += delta
                }
                if let self, !self.translatedText.isEmpty {
                    HistoryStore.shared.add(
                        HistoryItem(
                            id: UUID(), date: Date(), mode: queryMode.rawValue,
                            sourceText: text, translatedText: self.translatedText,
                            sourceLang: sourceLang, targetLang: targetLang))
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self?.errorMessage = error.localizedDescription
                }
            }
            self?.isTranslating = false
        }
    }

    /// Restore a history entry into the window without re-translating.
    func restore(_ item: HistoryItem) {
        currentTask?.cancel()
        isTranslating = false
        errorMessage = nil
        inputText = item.sourceText
        translatedText = item.translatedText
        if let restoredMode = TranslateMode(rawValue: item.mode) {
            mode = restoredMode
        }
        querySeq &+= 1
    }

    func showTranslatorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("translator") == true
        }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
