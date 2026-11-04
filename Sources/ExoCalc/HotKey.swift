import AppKit
import Carbon

/// Global hotkey via Carbon RegisterEventHotKey — needs no Accessibility permission.
final class HotKey {
    static let shared = HotKey()
    var action: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    @discardableResult
    func register(code: UInt32, mods: UInt32) -> Bool {
        installHandler()
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4558_434C), id: 1) // 'EXCL'
        let status = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let r = ref {
            UnregisterEventHotKey(r)
            ref = nil
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

enum HotKeyFormat {
    static let keyNames: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        24: "=", 27: "-", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        49: "Space", 36: "↩", 48: "⇥",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func isFunctionKey(_ code: Int) -> Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(code)
    }

    static func string(code: Int, mods: Int) -> String {
        var s = ""
        if mods & controlKey != 0 { s += "⌃" }
        if mods & optionKey != 0 { s += "⌥" }
        if mods & shiftKey != 0 { s += "⇧" }
        if mods & cmdKey != 0 { s += "⌘" }
        return s + (keyNames[code] ?? "#\(code)")
    }

    static func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        if f.contains(.shift) { m |= shiftKey }
        return m
    }
}
