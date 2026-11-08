import SwiftUI
import UIKit
import ExoCalcCore

/// Sheet, engine, rates and settings of the iPhone/iPad app.
final class CalcModel: ObservableObject {
    let rates: RateStore
    let engine: Engine
    private let d = UserDefaults.standard

    @Published var status = ""
    @Published var statusIsCopy = false
    @Published var ratesStatus = ""

    @Published var decimalSeparator: String { didSet { d.set(decimalSeparator, forKey: "decimalSeparator"); fixGrouping(); settingsChanged() } }
    @Published var groupingSeparator: String { didSet { d.set(groupingSeparator, forKey: "groupingSeparator"); fixGrouping(); settingsChanged() } }
    @Published var decimals: Int { didSet { d.set(decimals, forKey: "decimals"); settingsChanged() } }
    @Published var trimZeros: Bool { didSet { d.set(trimZeros, forKey: "trimZeros"); settingsChanged() } }
    @Published var dateFormat: String { didSet { d.set(dateFormat, forKey: "dateFormat"); settingsChanged() } }
    @Published var useNBU: Bool { didSet { d.set(useNBU, forKey: "useNBU"); rates.useNBU = useNBU; settingsChanged() } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize"); editor?.applyFont() } }
    @Published var language: String {
        didSet { d.set(language, forKey: "language"); L10n.lang = L10n.resolve(language); settingsChanged() }
    }

    /// The editor registers itself here.
    weak var editor: CalcTextView?
    private(set) var text: String
    private var statusUntil = Date.distantPast
    private var saveWork: DispatchWorkItem?

    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("ExoCalc", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    private static var sheetURL: URL { dir.appendingPathComponent("sheet.txt") }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "decimalSeparator": ".", "groupingSeparator": ",", "decimals": 2, "trimZeros": true,
            "dateFormat": "dmy", "useNBU": true, "language": "", "fontSize": 15.0,
        ])
        decimalSeparator = d.string(forKey: "decimalSeparator") ?? "."
        groupingSeparator = d.string(forKey: "groupingSeparator") ?? ","
        decimals = d.integer(forKey: "decimals")
        trimZeros = d.bool(forKey: "trimZeros")
        dateFormat = d.string(forKey: "dateFormat") ?? "dmy"
        useNBU = d.bool(forKey: "useNBU")
        fontSize = d.double(forKey: "fontSize")
        let lang = d.string(forKey: "language") ?? ""
        language = lang
        L10n.lang = L10n.resolve(lang)

        let rs = RateStore(cacheURL: CalcModel.dir.appendingPathComponent("rates.json"))
        rs.useNBU = d.bool(forKey: "useNBU")
        rates = rs
        engine = Engine(rates: rs)
        text = ""
        engine.settings = calcSettings
        if let saved = try? String(contentsOf: CalcModel.sheetURL, encoding: .utf8) {
            text = saved
        } else {
            text = Examples.welcomeLines(hotkey: nil).joined(separator: "\n")
        }
        rates.onChange = { [weak self] in
            self?.editor?.recalc()
            self?.updateRatesStatus()
        }
        updateRatesStatus()
        refreshRatesIfNeeded()
    }

    var calcSettings: CalcSettings {
        var s = CalcSettings()
        s.decimalSeparator = decimalSeparator == "," ? "," : "."
        s.groupingSeparator = groupingSeparator
        s.decimals = max(0, min(10, decimals))
        s.trimZeros = trimZeros
        s.dateFormat = dateFormat
        return s
    }

    private func fixGrouping() {
        if groupingSeparator == decimalSeparator {
            groupingSeparator = decimalSeparator == "," ? " " : ","
        }
    }

    private func settingsChanged() {
        engine.settings = calcSettings
        editor?.recalc()
        updateRatesStatus()
    }

    // MARK: - Sheet

    func textChanged(_ s: String) {
        text = s
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }

    func save() {
        try? text.write(to: CalcModel.sheetURL, atomically: true, encoding: .utf8)
    }

    func evaluate(_ lines: [String]) -> [LineResult] {
        engine.evaluate(lines: lines)
    }

    func insertExamples() {
        editor?.appendText("\n" + Examples.welcomeLines(hotkey: nil).joined(separator: "\n"))
    }

    func insertLine(_ s: String) {
        editor?.appendText(s)
    }

    func clearSheet() {
        editor?.replaceAll("")
    }

    // MARK: - Copy

    func copy(line: String, result: String, full: Bool) {
        let s = full ? "\(Examples.expression(ofLine: line)) = \(result)" : result
        UIPasteboard.general.string = s
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flash(tr("copied", s))
    }

    func copyAll(lines: [String], results: [LineResult]) {
        let out = zip(lines, results).map { line, r -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let d = r.display, !t.isEmpty, !t.hasPrefix("#") else { return line }
            return "\(Examples.expression(ofLine: line)) = \(d)"
        }
        UIPasteboard.general.string = out.joined(separator: "\n")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flash(tr("copiedAll"))
    }

    func flash(_ s: String) {
        status = s
        statusIsCopy = true
        statusUntil = Date().addingTimeInterval(2.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self = self, Date() >= self.statusUntil else { return }
            self.statusIsCopy = false
            self.status = ""
        }
    }

    // MARK: - Rates

    func refreshRatesIfNeeded() {
        if rates.isStale { refreshRates() }
    }

    func refreshRates() {
        rates.refresh { [weak self] _ in self?.updateRatesStatus() }
    }

    func updateRatesStatus() {
        var s: String
        if let u = rates.updated {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            s = tr("ratesUpdated", f.string(from: u))
        } else {
            s = tr("ratesNotLoaded")
        }
        if useNBU, let nd = rates.nbuDate { s += " · " + tr("nbuOn", nd) }
        if let r = rates.rate("USD", "UAH") { s += " · 1 USD = \(engine.number(r, decimals: 4)) UAH" }
        ratesStatus = s
    }
}
