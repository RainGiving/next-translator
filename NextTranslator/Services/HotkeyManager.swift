import Carbon
import Foundation

struct HotkeySpec: Hashable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let hotkeySignature: OSType = 0x4E54524E

    private var nextHotkeyID: UInt32 = 1
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func register(_ spec: HotkeySpec, handler: @escaping @MainActor () -> Void) {
        installEventHandlerIfNeeded()

        let id: UInt32 = nextHotkeyID
        nextHotkeyID &+= 1

        let hotkeyID = EventHotKeyID(signature: Self.hotkeySignature, id: id)
        var hotkeyRef: EventHotKeyRef?
        let status: OSStatus = RegisterEventHotKey(
            spec.keyCode,
            spec.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            Self.printError("Hotkey registration failed: \(status)")
            return
        }

        hotkeyRefs[id] = hotkeyRef
        handlers[id] = handler
    }

    func unregisterAll() {
        for hotkeyRef in hotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }

        hotkeyRefs.removeAll()
        handlers.removeAll()
    }
}

private extension HotkeyManager {
    func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData: UnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
        let status: OSStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if status != noErr {
            Self.printError("Hotkey event handler installation failed: \(status)")
        }
    }

    func invokeHandler(id: UInt32) {
        handlers[id]?()
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }

    var hotkeyID = EventHotKeyID()
    let status: OSStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )

    guard status == noErr else { return status }

    let manager: HotkeyManager = Unmanaged<HotkeyManager>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let id: UInt32 = hotkeyID.id

    Task { @MainActor in
        manager.invokeHandler(id: id)
    }

    return noErr
}
