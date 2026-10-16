import Carbon.HIToolbox

/// Global hotkey via Carbon (works without Accessibility permission).
enum HotKey {
    private static var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    @discardableResult
    static func register(keyCode: Int = kVK_ANSI_9, modifiers: Int = cmdKey | shiftKey,
                         _ action: @escaping () -> Void) -> Bool {
        handler = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4C53_4E50), id: 1) // 'LSNP'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }
}
