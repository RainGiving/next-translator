import ServiceManagement
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var launchAtLoginError: String?

    private static let languages: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"),
        ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"), ("de", "Deutsch"),
        ("es", "Español"), ("ru", "Русский"), ("pt", "Português"),
    ]

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ActionsSettingsView()
                .tabItem {
                    Label("Actions", systemImage: "square.grid.2x2")
                }
        }
        .frame(width: 560)
        .frame(minHeight: 540)
    }

    private var generalTab: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: providerBinding) {
                    ForEach(ProviderPreset.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                TextField("API Base URL", text: baseURLBinding)
                    .autocorrectionDisabled()
                    .disabled(currentProvider != .custom)

                SecureField("API Key", text: binding(\.apiKey))
                TextField("Model", text: binding(\.apiModel))
                    .autocorrectionDisabled()
            }

            Section("Behavior") {
                Picker("Default mode", selection: binding(\.defaultMode)) {
                    ForEach(TranslateMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }

                Toggle("Launch at login", isOn: launchAtLoginBinding)

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Languages") {
                Picker("Target language", selection: binding(\.targetLanguage)) {
                    ForEach(Self.languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                Picker("When source equals target", selection: binding(\.secondaryTargetLanguage)) {
                    ForEach(Self.languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            }

            Section("About") {
                Text("\(appName) \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                store.settings[keyPath: keyPath] = newValue
                try? store.save()
            }
        )
    }

    private var currentProvider: ProviderPreset {
        ProviderPreset.matching(baseURL: store.settings.apiBaseURL)
    }

    private var providerBinding: Binding<ProviderPreset> {
        Binding(
            get: { currentProvider },
            set: { provider in
                if provider == .custom {
                    guard currentProvider != .custom else { return }

                    store.settings.apiBaseURL = ""
                    try? store.save()
                    return
                }

                guard let apiBaseURL: String = provider.apiBaseURL else { return }

                store.settings.apiBaseURL = apiBaseURL
                try? store.save()
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        currentProvider == .custom
            ? binding(\.apiBaseURL)
            : .constant(store.settings.apiBaseURL)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Next Translator"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
    }

    private enum ProviderPreset: String, CaseIterable, Identifiable {
        case openAI
        case deepSeek
        case moonshot
        case groq
        case ollama
        case custom

        var id: Self { self }

        var displayName: String {
            switch self {
            case .openAI:
                return "OpenAI"
            case .deepSeek:
                return "DeepSeek"
            case .moonshot:
                return "Moonshot"
            case .groq:
                return "Groq"
            case .ollama:
                return "Ollama"
            case .custom:
                return "Custom"
            }
        }

        var apiBaseURL: String? {
            switch self {
            case .openAI:
                return "https://api.openai.com"
            case .deepSeek:
                return "https://api.deepseek.com"
            case .moonshot:
                return "https://api.moonshot.cn"
            case .groq:
                return "https://api.groq.com/openai"
            case .ollama:
                return "http://127.0.0.1:11434/v1"
            case .custom:
                return nil
            }
        }

        static func matching(baseURL: String) -> ProviderPreset {
            let trimmedBaseURL: String = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

            return allCases.first { provider in
                guard let apiBaseURL: String = provider.apiBaseURL else { return false }
                return apiBaseURL == trimmedBaseURL
            } ?? .custom
        }
    }
}
