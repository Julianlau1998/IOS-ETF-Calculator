//
//  BaseRateService.swift
//  ETF Calculator
//

import Foundation

/// Keeps the German Basiszins (for the Vorabpauschale) up to date — fully automatically.
///
/// By law (§ 18 InvStG, § 203 BewG) the Basiszins is the yield of Federal
/// securities with annual coupons and 15 years residual maturity, derived from
/// the Bundesbank's term structure on the first trading day of the year.
/// The Bundesbank publishes zero-coupon rates (Svensson method) for 1…15 years;
/// the par yield computed from them matches the BMF's published values exactly
/// (2023: 2.55 %, 2024: 2.29 %, 2025: 2.53 %, 2026: 3.20 %).
///
/// A JSON file next to the privacy policy serves as a fallback:
///
///     { "rate": 3.20, "year": 2026 }
enum BaseRateService {
    static let fallbackURL = URL(string: "https://jlau.netlify.app/etf-calculator/basiszins.json")!
    private static let lastCheckKey = "tax.baseRateLastCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private struct Payload: Decodable {
        let rate: Double
        let year: Int
    }

    /// Fetches the latest rate at most once a day if automatic updates are on.
    static func refreshIfNeeded() async {
        let defaults = UserDefaults.standard
        let isAutomatic = defaults.object(forKey: TaxSettings.Key.baseRateAutomatic) as? Bool ?? true
        guard isAutomatic else { return }
        if let lastCheck = defaults.object(forKey: lastCheckKey) as? Date,
           Date.now.timeIntervalSince(lastCheck) < checkInterval { return }

        let currentYear = Calendar.current.component(.year, from: .now)
        var result = await bundesbankRate(year: currentYear)
        // In the first days of January the new year's value may not exist yet.
        if result == nil { result = await bundesbankRate(year: currentYear - 1) }
        if result == nil { result = await fallbackRate() }

        guard let result, (-1...10).contains(result.rate) else { return }
        defaults.set(result.rate, forKey: TaxSettings.Key.baseRate)
        defaults.set(result.year, forKey: TaxSettings.Key.baseRateYear)
        defaults.set(Date.now, forKey: lastCheckKey)
    }

    // MARK: Bundesbank

    /// Zero-coupon rates for 1…15 years on the first trading day of `year`.
    private static func bundesbankRate(year: Int) async -> (rate: Double, year: Int)? {
        var components = URLComponents(string: "https://api.statistiken.bundesbank.de/rest/data/BBSIS/D.I.ZST.ZI.EUR.S1311.B.A604..R.A.A._Z._Z.A")!
        components.queryItems = [
            URLQueryItem(name: "startPeriod", value: "\(year)-01-01"),
            URLQueryItem(name: "endPeriod", value: "\(year)-01-15"),
            URLQueryItem(name: "format", value: "csv"),
            URLQueryItem(name: "lang", value: "en")
        ]
        guard let url = components.url,
              let text = await download(url) else { return nil }
        guard let rates = firstCompleteCurve(in: text) else { return nil }
        return (parYield(zeroRates: rates), year)
    }

    /// Parses the Bundesbank CSV and returns the rates for maturities 1…15 of the first complete day.
    static func firstCompleteCurve(in csv: String) -> [Double]? {
        let rows = csv.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        guard let header = rows.first else { return nil }

        // Column index for each whole-year maturity, e.g. "...A604.R07XX.R..." → 7.
        var columns: [Int: Int] = [:]
        for (index, title) in header.enumerated() where !title.hasSuffix("_FLAGS") {
            guard let range = title.range(of: #"A604\.R(\d\d)XX\.R"#, options: .regularExpression) else { continue }
            let digits = title[range].dropFirst(6).prefix(2)
            if let maturity = Int(digits), (1...15).contains(maturity) {
                columns[maturity] = index
            }
        }
        guard columns.count == 15 else { return nil }

        for row in rows where row.first?.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let rates = (1...15).compactMap { maturity -> Double? in
                guard let index = columns[maturity], index < row.count else { return nil }
                return Double(row[index])
            }
            if rates.count == 15 { return rates }
        }
        return nil
    }

    /// Yield of a 15-year bond with annual coupons priced at par, rounded to two decimals.
    static func parYield(zeroRates: [Double]) -> Double {
        let discountFactors = zeroRates.enumerated().map { index, rate in
            pow(1 + rate / 100, -Double(index + 1))
        }
        let par = (1 - discountFactors[discountFactors.count - 1]) / discountFactors.reduce(0, +) * 100
        return (par * 100).rounded() / 100
    }

    // MARK: Fallback

    private static func fallbackRate() async -> (rate: Double, year: Int)? {
        guard let text = await download(fallbackURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)) else { return nil }
        return (payload.rate, payload.year)
    }

    private static func download(_ url: URL) async -> String? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
