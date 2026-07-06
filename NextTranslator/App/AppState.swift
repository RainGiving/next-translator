import AppKit
import SwiftUI

/// Application-wide state and service wiring. UI state that belongs to a
/// single view stays in that view; this object owns cross-cutting state:
/// the current query, streaming output, and window/service lifecycles.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Text waiting to be translated (set by PopClip IPC, hotkeys or the UI).
    @Published var inputText: String = ""
    /// Monotonic counter: every external hand-off bumps it so views can
    /// re-trigger a translation even when the text is unchanged.
    @Published var querySeq: UInt64 = 0

    private init() {}

    /// Called once from AppDelegate after launch.
    func startServices() {
        // IPC server and global hotkeys are attached here in later phases.
    }

    /// Hand a new text to the translator and bring the window to front.
    func handleIncomingText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = trimmed
        querySeq &+= 1
        showTranslatorWindow()
    }

    func showTranslatorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("translator") == true }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
