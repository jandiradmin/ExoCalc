import AppKit
import ExoCalcCore

/// Checks GitHub Releases for a newer ExoCalc and installs it in place.
final class Updater {
    static let shared = Updater()
    private let api = URL(string: "https://api.github.com/repos/jandiradmin/ExoCalc/releases/latest")!

    struct Release {
        let version: String
        let zipURL: URL
    }

    private(set) var available: Release?
    private(set) var installing = false
    /// Called on the main thread whenever `available` changes.
    var onChange: (() -> Void)?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func check(completion: ((Result<Release?, Error>) -> Void)? = nil) {
        var req = URLRequest(url: api, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ExoCalc/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self = self else { return }
            var result: Result<Release?, Error>
            if let err = err {
                result = .failure(err)
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String {
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = json["assets"] as? [[String: Any]] ?? []
                let zip = assets.first { ($0["name"] as? String) == "ExoCalc-macOS.zip" }
                if Updater.isNewer(version, than: self.currentVersion),
                   let s = zip?["browser_download_url"] as? String, let u = URL(string: s) {
                    result = .success(Release(version: version, zipURL: u))
                } else {
                    result = .success(nil)
                }
            } else {
                result = .failure(CalcError("GitHub"))
            }
            DispatchQueue.main.async {
                if case .success(let r) = result { self.available = r; self.onChange?() }
                completion?(result)
            }
        }.resume()
    }

    /// Downloads the zip, unpacks it, swaps the app bundle after we quit and relaunches.
    func install(completion: @escaping (Error?) -> Void) {
        guard let rel = available, !installing else { return }
        installing = true
        URLSession.shared.downloadTask(with: rel.zipURL) { [weak self] tmp, _, err in
            guard let self = self else { return }
            do {
                if let err = err { throw err }
                guard let tmp = tmp else { throw CalcError("download") }
                let fm = FileManager.default
                let dir = fm.temporaryDirectory.appendingPathComponent("ExoCalc-update-\(rel.version)")
                try? fm.removeItem(at: dir)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let zip = dir.appendingPathComponent("ExoCalc.zip")
                try fm.moveItem(at: tmp, to: zip)
                try Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
                let newApp = dir.appendingPathComponent("ExoCalc.app")
                guard fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/ExoCalc").path) else {
                    throw CalcError("ExoCalc.app")
                }
                let dest = Bundle.main.bundlePath
                guard fm.isWritableFile(atPath: (dest as NSString).deletingLastPathComponent) else {
                    throw CalcError((dest as NSString).deletingLastPathComponent)
                }
                let pid = ProcessInfo.processInfo.processIdentifier
                let script = """
                while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
                rm -rf "\(dest)" && mv "\(newApp.path)" "\(dest)" && xattr -cr "\(dest)"
                open "\(dest)"
                """
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", script]
                try p.run()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            } catch {
                DispatchQueue.main.async {
                    self.installing = false
                    completion(error)
                }
            }
        }.resume()
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw CalcError("\(tool) \(p.terminationStatus)") }
    }
}
