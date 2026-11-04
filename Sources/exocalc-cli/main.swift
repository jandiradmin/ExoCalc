import Foundation
import ExoCalcCore

// Usage:
//   exocalc-cli "600 usd in uah"
//   echo -e "a = 5\na * 2" | exocalc-cli
//   exocalc-cli --selftest

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--selftest" {
    exit(SelfTest.run() ? 0 : 1)
}

let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ExoCalc", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let rates = RateStore(cacheURL: dir.appendingPathComponent("rates.json"))
if let d = UserDefaults(suiteName: "com.jandiradmin.exocalc"), d.object(forKey: "useNBU") != nil {
    rates.useNBU = d.bool(forKey: "useNBU")
}
if rates.isStale {
    let sem = DispatchSemaphore(value: 0)
    rates.refresh(queue: DispatchQueue.global()) { _ in sem.signal() }
    _ = sem.wait(timeout: .now() + 12)
}

let engine = Engine(rates: rates)
if let d = UserDefaults(suiteName: "com.jandiradmin.exocalc") {
    if let sep = d.string(forKey: "decimalSeparator"), let c = sep.first { engine.settings.decimalSeparator = c }
    if let g = d.string(forKey: "groupingSeparator") { engine.settings.groupingSeparator = g }
    if d.object(forKey: "decimals") != nil { engine.settings.decimals = d.integer(forKey: "decimals") }
    if d.object(forKey: "trimZeros") != nil { engine.settings.trimZeros = d.bool(forKey: "trimZeros") }
}

var lines: [String] = []
if args.isEmpty {
    while let l = readLine() { lines.append(l) }
} else {
    lines = [args.joined(separator: " ")]
}

let results = engine.evaluate(lines: lines)
var failed = false
for (line, r) in zip(lines, results) {
    if let d = r.display {
        print(lines.count == 1 ? d : "\(line) = \(d)")
    } else if let err = r.error {
        FileHandle.standardError.write("ошибка: \(err)\n".data(using: .utf8)!)
        failed = true
    } else if lines.count > 1 {
        print(line)
    }
}
exit(failed ? 1 : 0)
