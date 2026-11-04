import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exchange rates, stored as "units of currency per 1 USD".
/// Sources: open.er-api.com (world), bank.gov.ua (NBU, UAH), CoinGecko (crypto).
public final class RateStore {
    public static let cryptoIDs: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "USDT": "tether", "USDC": "usd-coin", "BNB": "binancecoin",
        "SOL": "solana", "XRP": "ripple", "TON": "the-open-network", "TRX": "tron", "DOGE": "dogecoin",
        "LTC": "litecoin", "ADA": "cardano",
    ]

    public static let commonCodes: Set<String> = Set([
        "USD", "EUR", "UAH", "GBP", "JPY", "CNY", "CHF", "CAD", "AUD", "NZD", "PLN", "CZK", "HUF", "RON",
        "BGN", "SEK", "NOK", "DKK", "ISK", "TRY", "ILS", "AED", "SAR", "QAR", "GEL", "AMD", "AZN", "KZT",
        "MDL", "INR", "KRW", "SGD", "HKD", "THB", "VND", "IDR", "MYR", "PHP", "MXN", "BRL", "ARS", "CLP",
        "COP", "ZAR", "EGP", "XAU", "XAG",
    ]).union(RateStore.cryptoIDs.keys)

    public private(set) var perUSD: [String: Double] = ["USD": 1]
    public private(set) var updated: Date?
    public private(set) var nbuDate: String?
    public var useNBU = true {
        didSet { if oldValue != useNBU { rebuild() } }
    }
    public var onChange: (() -> Void)?

    private var market: [String: Double] = [:]
    private var nbu: [String: Double] = [:]      // UAH per 1 unit
    private var crypto: [String: Double] = [:]   // USD per 1 coin
    private let cacheURL: URL?
    private var loading = false
    private var lastAttempt: Date?

    private struct Cache: Codable {
        var market: [String: Double]
        var nbu: [String: Double]
        var crypto: [String: Double]
        var updated: Date?
        var nbuDate: String?
    }

    public init(cacheURL: URL?) {
        self.cacheURL = cacheURL
        loadCache()
        rebuild()
    }

    public func knows(_ code: String) -> Bool {
        perUSD[code] != nil || RateStore.commonCodes.contains(code)
    }

    /// True when rates should be refreshed: never loaded, older than 4 hours,
    /// or a source is missing (retried at most every 5 minutes).
    public var isStale: Bool {
        if let a = lastAttempt, Date().timeIntervalSince(a) < 300 { return false }
        guard let u = updated else { return true }
        if crypto.isEmpty || market.isEmpty { return true }
        return Date().timeIntervalSince(u) > 4 * 3600
    }

    /// How many `to` per 1 `from`.
    public func rate(_ from: String, _ to: String) -> Double? {
        guard let a = perUSD[from], let b = perUSD[to], a > 0 else { return nil }
        return b / a
    }

    /// For tests: fixed rates (units per 1 USD).
    public func setTestRates(_ r: [String: Double]) {
        market = r
        nbu = [:]
        crypto = [:]
        rebuild()
    }

    private func rebuild() {
        var r = market
        if useNBU, let usd = nbu["USD"], usd > 0 {
            r["UAH"] = usd
            for (code, uahPer) in nbu where uahPer > 0 && code != "UAH" {
                r[code] = usd / uahPer
            }
        }
        for (code, price) in crypto where price > 0 {
            r[code] = 1 / price
        }
        r["USD"] = 1
        perUSD = r
    }

    public func refresh(queue: DispatchQueue = .main, completion: ((Bool) -> Void)? = nil) {
        if loading {
            queue.async { completion?(false) }
            return
        }
        loading = true
        lastAttempt = Date()
        let group = DispatchGroup()
        let lock = NSLock()
        var newMarket: [String: Double]? = nil
        var newNBU: [String: Double]? = nil
        var newNBUDate: String? = nil
        var newCrypto: [String: Double]? = nil
        var backupCrypto: [String: Double]? = nil

        group.enter()
        RateStore.fetch("https://open.er-api.com/v6/latest/USD") { obj in
            if let dict = obj as? [String: Any], let rates = dict["rates"] as? [String: Any] {
                var m: [String: Double] = [:]
                for (k, v) in rates {
                    if let n = v as? NSNumber { m[k] = n.doubleValue }
                }
                lock.lock(); newMarket = m; lock.unlock()
            }
            group.leave()
        }

        group.enter()
        RateStore.fetch("https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json") { obj in
            if let arr = obj as? [[String: Any]] {
                var m: [String: Double] = [:]
                var date: String? = nil
                for item in arr {
                    if let cc = item["cc"] as? String, let r = item["rate"] as? NSNumber {
                        m[cc] = r.doubleValue
                    }
                    if date == nil { date = item["exchangedate"] as? String }
                }
                lock.lock(); newNBU = m; newNBUDate = date; lock.unlock()
            }
            group.leave()
        }

        group.enter()
        let ids = RateStore.cryptoIDs.values.sorted().joined(separator: ",")
        RateStore.fetch("https://api.coingecko.com/api/v3/simple/price?ids=\(ids)&vs_currencies=usd") { obj in
            if let dict = obj as? [String: Any] {
                var m: [String: Double] = [:]
                for (code, id) in RateStore.cryptoIDs {
                    if let e = dict[id] as? [String: Any], let p = e["usd"] as? NSNumber {
                        m[code] = p.doubleValue
                    }
                }
                lock.lock(); newCrypto = m; lock.unlock()
            }
            group.leave()
        }

        // Backup crypto source (Coinbase): rates are "coins per 1 USD".
        group.enter()
        RateStore.fetch("https://api.coinbase.com/v2/exchange-rates?currency=USD") { obj in
            if let dict = obj as? [String: Any], let data = dict["data"] as? [String: Any],
               let r = data["rates"] as? [String: Any] {
                var m: [String: Double] = [:]
                for code in RateStore.cryptoIDs.keys {
                    if let str = r[code] as? String, let perUSD = Double(str), perUSD > 0 { m[code] = 1 / perUSD }
                }
                lock.lock(); backupCrypto = m; lock.unlock()
            }
            group.leave()
        }

        group.notify(queue: queue) {
            self.loading = false
            var ok = false
            if let m = newMarket, !m.isEmpty { self.market = m; ok = true }
            if let n = newNBU, !n.isEmpty { self.nbu = n; self.nbuDate = newNBUDate; ok = true }
            if let c = newCrypto, !c.isEmpty {
                self.crypto = c
                ok = true
            } else if let c = backupCrypto, !c.isEmpty {
                self.crypto = c
                ok = true
            }
            if ok {
                self.updated = Date()
                self.rebuild()
                self.saveCache()
            }
            completion?(ok)
            self.onChange?()
        }
    }

    private static func fetch(_ urlString: String, _ done: @escaping (Any?) -> Void) {
        guard let url = URL(string: urlString) else { done(nil); return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("ExoCalc/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let data = data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                done(nil)
                return
            }
            done(try? JSONSerialization.jsonObject(with: data))
        }.resume()
    }

    private func loadCache() {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        market = c.market
        nbu = c.nbu
        crypto = c.crypto
        updated = c.updated
        nbuDate = c.nbuDate
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let c = Cache(market: market, nbu: nbu, crypto: crypto, updated: updated, nbuDate: nbuDate)
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
