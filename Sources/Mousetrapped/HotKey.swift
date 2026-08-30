import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey using the Carbon RegisterEventHotKey API.
/// Unlike NSEvent global monitors or CGEvent taps, this needs no Accessibility
/// or Input Monitoring permission — which matters, because this app has to
/// work when the machine is in a broken state.
final class HotKey {

    static let keyCodeDefaultsKey = "hotKeyCode"
    static let modifiersDefaultsKey = "hotKeyModifiers"

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    /// Default: Control + Option + Command + M
    static var savedKeyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: keyCodeDefaultsKey) as? UInt32
        return stored ?? UInt32(kVK_ANSI_M)
    }

    static var savedModifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: modifiersDefaultsKey) as? UInt32
        return stored ?? UInt32(controlKey | optionKey | cmdKey)
    }

    init?(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            var hotKeyID = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            }
            MTLog.log("HotKey: callback fired (id=\(hotKeyID.id))")
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            hotKey.handler()
            return noErr
        }
        // GetApplicationEventTarget, not GetEventDispatcherTarget: the
        // dispatcher target can silently stop delivering hotkey events to
        // background/accessory apps after an activation cycle.
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1,
                                                &eventType,
                                                Unmanaged.passUnretained(self).toOpaque(),
                                                &eventHandlerRef)
        MTLog.log("HotKey: InstallEventHandler status=\(installStatus)")
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D_54_52_50) /* 'MTRP' */, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        MTLog.log("HotKey: RegisterEventHotKey keyCode=\(keyCode) mods=\(carbonModifiers) status=\(registerStatus)")
        guard registerStatus == noErr else {
            if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
