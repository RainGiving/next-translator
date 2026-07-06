import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    private static let languages: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"),
        ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"), ("de", "Deutsch"),
        ("es", "Español"), ("ru", "Русский"), ("pt", "Português"),
    ]

    var body: some View {
        Form {
            Section("Provider") {
                SecureField("API Key", text: binding(\.apiKey))
                TextField("API Base URL", text: binding(\.apiBaseURL))
                    .autocorrectionDisabled()
                TextField("Model", text: binding(\.apiModel))
                    .autocorrectionDisabled()
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
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 340)
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
}
