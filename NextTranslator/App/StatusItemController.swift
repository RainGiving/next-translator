import AppKit

/// Menu bar presence. A left click toggles the translator window straight
/// away; a right click (or control-click) shows the app menu. MenuBarExtra
/// cannot tell the two apart, so this drives NSStatusItem directly.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "character.bubble",
                accessibilityDescription: String(localized: "Next Translator"))
            button.image = image?.withSymbolConfiguration(.init(scale: .large))
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let item = statusItem else { return }

        let event = NSApp.currentEvent
        let isMenuClick =
            event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isMenuClick {
            showMenu(for: item)
        } else {
            AppState.shared.toggleTranslatorWindow()
        }
    }

    private func showMenu(for item: NSStatusItem) {
        let menu = NSMenu()

        menu.addItem(makeItem(String(localized: "Show Translator"), action: #selector(showTranslator)))
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Settings…"), action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(
            makeItem(
                String(localized: "Quit Next Translator"), action: #selector(quit),
                keyEquivalent: "q"))

        // Attaching the menu only for this click keeps the button's plain
        // action behaviour for left clicks.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func makeItem(
        _ title: String, action: Selector, keyEquivalent: String = ""
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.target = self
        return menuItem
    }

    @objc private func showTranslator() {
        AppState.shared.showTranslatorWindow()
    }

    /// Routes to the SwiftUI Settings scene through the responder chain.
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
        _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
