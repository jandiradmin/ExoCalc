import Foundation
import Combine

enum Storage {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("ExoCalc", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static var sheetURL: URL { dir.appendingPathComponent("sheet.json") }
    static var historyURL: URL { dir.appendingPathComponent("history.json") }
    static var ratesURL: URL { dir.appendingPathComponent("rates.json") }

    struct Sheet: Codable {
        var text: String
        var selection: Int
        var scrollY: Double
    }

    static func loadSheet() -> Sheet? {
        guard let data = try? Data(contentsOf: sheetURL) else { return nil }
        return try? JSONDecoder().decode(Sheet.self, from: data)
    }

    static func saveSheet(_ s: Sheet) {
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: sheetURL, options: .atomic)
        }
    }
}

final class History: ObservableObject {
    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var expr: String
        var result: String
        var line: String { "\(expr) = \(result)" }
    }

    @Published private(set) var entries: [Entry] = []

    init() {
        if let data = try? Data(contentsOf: Storage.historyURL),
           let e = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = e
        }
    }

    func add(expr: String, result: String) {
        let ex = expr.trimmingCharacters(in: .whitespaces)
        guard !ex.isEmpty else { return }
        if let first = entries.first, first.expr == ex, first.result == result { return }
        entries.removeAll { $0.expr == ex && $0.result == result }
        entries.insert(Entry(date: Date(), expr: ex, result: result), at: 0)
        if entries.count > 2000 { entries.removeLast(entries.count - 2000) }
        save()
    }

    func remove(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Storage.historyURL, options: .atomic)
        }
    }
}
