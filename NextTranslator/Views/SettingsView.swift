import ServiceManagement
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var actionStore = ActionStore.shared
    @State private var launchAtLoginError: String?
    @State private var showRelaunchAlert = false

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
        .alert("Relaunch to apply the new language?", isPresented: $showRelaunchAlert) {
            Button("Relaunch Now") { relaunchApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The interface language changes the next time Next Translator starts.")
        }
    }

    private var generalTab: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: activeProviderBinding) {
                    ForEach(store.settings.providers) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }

                if activeProvider.isPreset {
                    LabeledContent("API Base URL") {
                        Text(activeProvider.baseURL)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    TextField("Provider Name", text: providerField(\.name))
                    TextField("API Base URL", text: providerField(\.baseURL))
                        .autocorrectionDisabled()
                }

                SecureField("API Key", text: providerField(\.apiKey))
                TextField("Model", text: providerField(\.model))
                    .autocorrectionDisabled()

                HStack {
                    Button("Add Custom Provider", systemImage: "plus") {
                        addCustomProvider()
                    }

                    Spacer()

                    if !activeProvider.isPreset {
                        Button("Remove Provider", role: .destructive) {
                            removeActiveProvider()
                        }
                    }
                }
                .buttonStyle(.borderless)
            }

            Section("Behavior") {
                Picker("Default mode", selection: binding(\.defaultMode)) {
                    ForEach(actionStore.actions) { action in
                        Text(action.localizedName).tag(action.builtinMode ?? action.id.uuidString)
                    }
                }

                Toggle("Hide when losing focus", isOn: binding(\.hideOnFocusLoss))

                HStack {
                    Text("Show window")
                    Spacer()
                    KeyRecorderView(
                        keyCode: binding(\.showWindowKeyCode),
                        carbonModifiers: binding(\.showWindowModifiers)
                    )
                }

                HStack {
                    Text("Translate selection")
                    Spacer()
                    KeyRecorderView(
                        keyCode: binding(\.selectionKeyCode),
                        carbonModifiers: binding(\.selectionModifiers)
                    )
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
                Picker("App language", selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("History") {
                Picker("Keep history", selection: historyRetentionBinding) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
            }

            Section("About") {
                Text("\(appName) \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(
                    "GitHub",
                    destination: URL(string: "https://github.com/RainGiving/next-translator")!
                )
                .font(.caption)
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

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { store.settings.appLanguage },
            set: { language in
                guard language != store.settings.appLanguage else { return }
                store.settings.appLanguage = language
                try? store.save()
                language.applyOverride()
                showRelaunchAlert = true
            }
        )
    }

    /// Relaunches into a fresh instance; the IPC server unlinks the stale
    /// socket on start, so the hand-off is safe.
    private func relaunchApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration
        ) { application, _ in
            // Only hand off when the new instance actually launched;
            // otherwise stay alive rather than quitting into nothing.
            guard application != nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Tightening the window prunes stored entries right away.
    private var historyRetentionBinding: Binding<HistoryRetention> {
        Binding(
            get: { store.settings.historyRetention },
            set: { retention in
                store.settings.historyRetention = retention
                try? store.save()
                HistoryStore.shared.pruneExpired()
            }
        )
    }

    private var activeProvider: APIProvider {
        store.settings.activeProvider
    }

    private var activeProviderBinding: Binding<UUID> {
        Binding(
            get: { store.settings.activeProviderID },
            set: { id in
                store.settings.activeProviderID = id
                try? store.save()
            }
        )
    }

    /// Binds one field of the active provider, persisting on every change.
    private func providerField(_ keyPath: WritableKeyPath<APIProvider, String>) -> Binding<String> {
        Binding(
            get: { store.settings.activeProvider[keyPath: keyPath] },
            set: { newValue in
                guard
                    let index = store.settings.providers.firstIndex(where: {
                        $0.id == store.settings.activeProviderID
                    })
                else { return }
                store.settings.providers[index][keyPath: keyPath] = newValue
                try? store.save()
            }
        )
    }

    private func addCustomProvider() {
        let provider: APIProvider = APIProvider(
            id: UUID(), preset: nil, name: String(localized: "New Provider"),
            baseURL: "", apiKey: "", model: "")
        store.settings.providers.append(provider)
        store.settings.activeProviderID = provider.id
        try? store.save()
    }

    private func removeActiveProvider() {
        guard
            let index = store.settings.providers.firstIndex(where: {
                $0.id == store.settings.activeProviderID
            }),
            !store.settings.providers[index].isPreset
        else { return }
        store.settings.providers.remove(at: index)
        store.settings.activeProviderID = store.settings.providers.first?.id ?? UUID()
        try? store.save()
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
            ?? String(localized: "Next Translator")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
    }
}
