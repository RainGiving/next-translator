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

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.install()
        AppState.shared.startServices()
    }

    /// Menu bar app: hiding or closing the translator window must never quit
    /// the app. Without this, SwiftUI terminates once its only Window scene
    /// goes away (e.g. the status item click that toggles the window off).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
