import SwiftUI

@main
struct NextTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared


    var body: some Scene {
        Window("Next Translator", id: "translator") {
            TranslatorView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 620, height: 640)

        MenuBarExtra("Next Translator", systemImage: "character.bubble") {
            Button("Show Translator") {
                appState.showTranslatorWindow()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            Divider()
            Button("Quit Next Translator") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.startServices()
    }
}
