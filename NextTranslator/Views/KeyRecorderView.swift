import AppKit
import Carbon.HIToolbox
import SwiftUI

struct KeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var carbonModifiers: UInt32

    @State private var isRecording: Bool = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? String(localized: "Press keys…") : Self.displayText(keyCode: keyCode, carbonModifiers: carbonModifiers)) {
            startRecording()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isRecording ? .accentColor : .secondary)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        isRecording = false
    }

    private func handleKeyDown(_ event: NSEvent) {
        if UInt32(event.keyCode) == UInt32(kVK_Escape) {
            stopRecording()
            return
        }

        let modifiers: UInt32 = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            return
        }

        keyCode = UInt32(event.keyCode)
        carbonModifiers = modifiers
        stopRecording()
    }

    private static func displayText(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        "\(modifierText(carbonModifiers))\(keyText(keyCode))"
    }

    private static func modifierText(_ carbonModifiers: UInt32) -> String {
        var text: String = ""

        if carbonModifiers & UInt32(controlKey) != 0 {
            text += "⌃"
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            text += "⌥"
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            text += "⇧"
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            text += "⌘"
        }

        return text
    }

    private static func keyText(_ keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "key#\(keyCode)"
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0

        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }

        return modifiers
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
    ]
}
