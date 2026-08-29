import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKey {
    static let shared = HotKey()

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private static let signature: OSType = 0x4D_49_4E_4F

    private init() {}

    private(set) var descriptor: String = ""

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == HotKey.signature else { return noErr }
            Task { @MainActor in HotKey.shared.fire() }
            return noErr
        }, 1, &eventType, nil, &handler)

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        descriptor = Self.describe(keyCode: keyCode, modifiers: modifiers)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        descriptor = ""
    }

    fileprivate func fire() { action?() }

    struct Choice: Identifiable, Hashable {
        var id: String { label }
        var label: String
        var keyCode: UInt32
        var modifiers: UInt32
    }

    static let choices: [Choice] = [
        Choice(label: "⌥⌘N", keyCode: UInt32(kVK_ANSI_N),
               modifiers: UInt32(optionKey | cmdKey)),
        Choice(label: "⌃⌥N", keyCode: UInt32(kVK_ANSI_N),
               modifiers: UInt32(controlKey | optionKey)),
        Choice(label: "⌥⌘Space", keyCode: UInt32(kVK_Space),
               modifiers: UInt32(optionKey | cmdKey)),
        Choice(label: "⌃⌥Space", keyCode: UInt32(kVK_Space),
               modifiers: UInt32(controlKey | optionKey)),
        Choice(label: "F13", keyCode: UInt32(kVK_F13), modifiers: 0),
    ]

    static func choice(named label: String) -> Choice? {
        choices.first { $0.label == label }
    }

    private static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        choices.first { $0.keyCode == keyCode && $0.modifiers == modifiers }?.label ?? "custom"
    }
}
