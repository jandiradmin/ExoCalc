import AppKit
import Carbon
import Combine
import ExoCalcCore

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var decimalSeparator: String { didSet { d.set(decimalSeparator, forKey: "decimalSeparator"); fixGrouping() } }
    @Published var groupingSeparator: String { didSet { d.set(groupingSeparator, forKey: "groupingSeparator"); fixGrouping() } }
    @Published var decimals: Int { didSet { d.set(decimals, forKey: "decimals") } }
    @Published var trimZeros: Bool { didSet { d.set(trimZeros, forKey: "trimZeros") } }
    @Published var fontName: String { didSet { d.set(fontName, forKey: "fontName") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var hotKeyCode: Int { didSet { d.set(hotKeyCode, forKey: "hotKeyCode") } }
    @Published var hotKeyMods: Int { didSet { d.set(hotKeyMods, forKey: "hotKeyMods") } }
    @Published var useNBU: Bool { didSet { d.set(useNBU, forKey: "useNBU") } }
    @Published var showHints: Bool { didSet { d.set(showHints, forKey: "showHints") } }
    @Published var hideOnDeactivate: Bool { didSet { d.set(hideOnDeactivate, forKey: "hideOnDeactivate") } }
    @Published var alwaysOnTop: Bool { didSet { d.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var language: String { didSet { d.set(language, forKey: "language"); L10n.lang = L10n.resolve(language) } }
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock") } }
    @Published var showInMenuBar: Bool { didSet { d.set(showInMenuBar, forKey: "showInMenuBar") } }
    /// Not persisted: shown in Settings.
    @Published var ratesStatus: String = ""

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "decimalSeparator": ".", "groupingSeparator": ",", "decimals": 2, "trimZeros": true,
            "fontName": "", "fontSize": 15.0,
            "hotKeyCode": kVK_ANSI_C, "hotKeyMods": controlKey | optionKey,
            "language": "", "showInDock": true, "showInMenuBar": true,
            "useNBU": true, "showHints": true, "hideOnDeactivate": false, "alwaysOnTop": false,
        ])
        decimalSeparator = d.string(forKey: "decimalSeparator") ?? "."
        groupingSeparator = d.string(forKey: "groupingSeparator") ?? ","
        decimals = d.integer(forKey: "decimals")
        trimZeros = d.bool(forKey: "trimZeros")
        fontName = d.string(forKey: "fontName") ?? ""
        fontSize = d.double(forKey: "fontSize")
        hotKeyCode = d.integer(forKey: "hotKeyCode")
        hotKeyMods = d.integer(forKey: "hotKeyMods")
        useNBU = d.bool(forKey: "useNBU")
        showHints = d.bool(forKey: "showHints")
        hideOnDeactivate = d.bool(forKey: "hideOnDeactivate")
        alwaysOnTop = d.bool(forKey: "alwaysOnTop")
        language = d.string(forKey: "language") ?? ""
        showInDock = d.bool(forKey: "showInDock")
        showInMenuBar = d.bool(forKey: "showInMenuBar")
        // Old default ⌥⌘= clashes with macOS Zoom — move to ⌃⌥C.
        if hotKeyCode == kVK_ANSI_Equal && hotKeyMods == (cmdKey | optionKey) {
            hotKeyCode = kVK_ANSI_C
            hotKeyMods = controlKey | optionKey
        }
        L10n.lang = L10n.resolve(language)
    }

    private func fixGrouping() {
        if groupingSeparator == decimalSeparator {
            groupingSeparator = decimalSeparator == "," ? " " : ","
        }
    }

    var calcSettings: CalcSettings {
        var s = CalcSettings()
        s.decimalSeparator = decimalSeparator == "," ? "," : "."
        s.groupingSeparator = groupingSeparator
        s.decimals = max(0, min(10, decimals))
        s.trimZeros = trimZeros
        return s
    }

    func font(size: CGFloat? = nil) -> NSFont {
        let sz = size ?? CGFloat(fontSize)
        if !fontName.isEmpty,
           let f = NSFontManager.shared.font(withFamily: fontName, traits: [], weight: 5, size: sz) {
            return f
        }
        return NSFont.monospacedSystemFont(ofSize: sz, weight: .regular)
    }

    func resultFont() -> NSFont {
        let sz = CGFloat(fontSize)
        if fontName.isEmpty { return NSFont.monospacedSystemFont(ofSize: sz, weight: .medium) }
        return font()
    }

    static func monospacedFamilies() -> [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        var fams = Set<String>()
        for n in names {
            if let f = NSFont(name: n, size: 12), let fam = f.familyName, !fam.hasPrefix(".") {
                fams.insert(fam)
            }
        }
        return fams.sorted()
    }
}

enum Theme {
    static let bg = NSColor(srgbRed: 0.125, green: 0.13, blue: 0.14, alpha: 1)
    static let text = NSColor(white: 0.88, alpha: 1)
    static let number = NSColor(white: 0.98, alpha: 1)
    static let unit = NSColor(srgbRed: 0.56, green: 0.76, blue: 0.95, alpha: 1)
    static let keyword = NSColor(srgbRed: 0.78, green: 0.62, blue: 0.95, alpha: 1)
    static let function = NSColor(srgbRed: 0.95, green: 0.76, blue: 0.47, alpha: 1)
    static let variable = NSColor(srgbRed: 0.95, green: 0.62, blue: 0.62, alpha: 1)
    static let comment = NSColor(white: 0.46, alpha: 1)
    static let result = NSColor(srgbRed: 0.6, green: 0.84, blue: 0.24, alpha: 1)
    static let hint = NSColor(srgbRed: 0.92, green: 0.5, blue: 0.4, alpha: 0.9)
    static let status = NSColor(white: 0.5, alpha: 1)

    static func color(_ k: HKind) -> NSColor {
        switch k {
        case .number: return number
        case .unit: return unit
        case .keyword: return keyword
        case .function: return function
        case .variable: return variable
        case .comment, .label: return comment
        case .error: return hint
        }
    }
}
