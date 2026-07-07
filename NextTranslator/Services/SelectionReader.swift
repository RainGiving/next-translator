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
        let originalItems: [SavedPasteboardItem] = snapshotPasteboardItems(from: pasteboard)
        let originalChangeCount: Int = pasteboard.changeCount

        sendCopyShortcut()

        var copiedString: String?
        var copiedChangeCount: Int?
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let currentChangeCount: Int = pasteboard.changeCount
            guard currentChangeCount != originalChangeCount else { continue }

            copiedString = pasteboard.string(forType: .string)
            copiedChangeCount = currentChangeCount
            break
        }

        guard let copiedChangeCount else {
            return nil
        }

        restorePasteboardItems(originalItems, ifChangeCountIs: copiedChangeCount, on: pasteboard)

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

    static func snapshotPasteboardItems(from pasteboard: NSPasteboard) -> [SavedPasteboardItem] {
        pasteboard.pasteboardItems?.map { item in
            let entries: [SavedPasteboardItem.Entry] = item.types.compactMap { type in
                guard let data: Data = item.data(forType: type) else { return nil }
                return SavedPasteboardItem.Entry(type: type, data: Data(data))
            }
            return SavedPasteboardItem(entries: entries)
        } ?? []
    }

    static func restorePasteboardItems(
        _ savedItems: [SavedPasteboardItem],
        ifChangeCountIs expectedChangeCount: Int,
        on pasteboard: NSPasteboard
    ) {
        guard pasteboard.changeCount == expectedChangeCount else {
            return
        }

        pasteboard.clearContents()

        let restoredItems: [NSPasteboardItem] = savedItems.map { savedItem in
            let item = NSPasteboardItem()
            for entry in savedItem.entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }

    struct SavedPasteboardItem {
        let entries: [Entry]

        struct Entry {
            let type: NSPasteboard.PasteboardType
            let data: Data
        }
    }
}
