import AppKit
import ApplicationServices
import Carbon

enum SelectionReader {
    static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func readSelectedText() async -> String? {
        await Task.detached(priority: .userInitiated) {
            if let selectedText = readSelectedTextUsingAccessibility() {
                return selectedText
            }

            return await readSelectedTextUsingPasteboard()
        }.value
    }
}

private extension SelectionReader {
    static func readSelectedTextUsingAccessibility() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedStatus: AXError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedStatus == .success, let focusedValue else {
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        var selectedValue: CFTypeRef?
        let selectedStatus: AXError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )

        guard selectedStatus == .success,
              let selectedText = selectedValue as? String,
              !selectedText.isEmpty else {
            return nil
        }

        return selectedText
    }

    static func readSelectedTextUsingPasteboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let originalString: String? = pasteboard.string(forType: .string)
        let originalChangeCount: Int = pasteboard.changeCount

        sendCopyShortcut()

        var copiedString: String?
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard pasteboard.changeCount != originalChangeCount else { continue }

            copiedString = pasteboard.string(forType: .string)
            break
        }

        restorePasteboardString(originalString)

        guard let copiedString, !copiedString.isEmpty else {
            return nil
        }

        return copiedString
    }

    static func sendCopyShortcut() {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: false
        ) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    static func restorePasteboardString(_ string: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let string {
            pasteboard.setString(string, forType: .string)
        }
    }
}
