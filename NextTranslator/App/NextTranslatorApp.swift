import SwiftUI

@main
struct NextTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some Scene {
        Window("Next Translator", id: "translator") {
            TranslatorView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 620, height: 640)

        MenuBarExtra {
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
        } label: {
            // Custom template asset: the system `character.bubble` symbol is
            // locale-aware and renders a CJK glyph on Chinese systems; we
            // always want the letter-A bubble.
            Image(nsImage: Self.menuBarIcon)
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
