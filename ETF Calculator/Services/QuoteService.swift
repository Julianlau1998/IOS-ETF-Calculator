//
//  QuoteService.swift
//  ETF Calculator
//

import Foundation

/// Looks up ETFs by ISIN and fetches their latest prices (Premium).
///
/// Uses EODHD (eodhd.com), which covers Xetra and US exchanges and supports
/// ISIN search. The API key is read from the Info.plist key `QuoteAPIKey`
/// (set via the `QUOTE_API_KEY` build setting). Without a key the service is
/// unavailable and prices can be entered manually.
enum QuoteService {
    struct Listing: Hashable {
        let symbol: String
        let name: String
        let currency: String
        let price: Double?
    }

    enum QuoteError: LocalizedError {
        case notConfigured, notFound, network

        var errorDescription: String? {
            switch self {
            case .notConfigured: String(localized: "Automatic prices aren't available. Enter the price manually.")
            case .notFound: String(localized: "No listing was found for this ISIN.")
            case .network: String(localized: "Prices couldn't be loaded. Check your internet connection.")
            }
        }
    }

    private static var apiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "QuoteAPIKey") as? String
        guard let key, !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    static var isAvailable: Bool { apiKey != nil }

    /// Finds the best listing for an ISIN, preferring the given currency and Xetra.
    static func lookup(isin: String, preferredCurrency: String) async throws -> Listing {
        guard let apiKey else { throw QuoteError.notConfigured }
        struct Result: Decodable {
            let Code: String
            let Exchange: String
            let Name: String
            let Currency: String?
            let previousClose: Double?
        }
        let url = URL(string: "https://eodhd.com/api/search/\(isin)?api_token=\(apiKey)&fmt=json")!
        let results: [Result] = try await fetch(url)
        let preferredExchanges = ["XETRA", "F", "US", "LSE", "AS", "PA", "SW"]
        let ranked = results.sorted { a, b in
            let aCurrency = a.Currency == preferredCurrency, bCurrency = b.Currency == preferredCurrency
            if aCurrency != bCurrency { return aCurrency }
            let aRank = preferredExchanges.firstIndex(of: a.Exchange) ?? 99
            let bRank = preferredExchanges.firstIndex(of: b.Exchange) ?? 99
            return aRank < bRank
        }
        guard let best = ranked.first else { throw QuoteError.notFound }
        return Listing(symbol: "\(best.Code).\(best.Exchange)", name: best.Name, currency: best.Currency ?? preferredCurrency, price: best.previousClose)
    }

    /// Latest (delayed) prices for several symbols in one request.
    static func prices(for symbols: [String]) async throws -> [String: Double] {
        guard let apiKey else { throw QuoteError.notConfigured }
        guard let first = symbols.first else { return [:] }
        struct Quote: Decodable {
            let code: String
            let close: Double?
            let previousClose: Double?
        }
        var components = URLComponents(string: "https://eodhd.com/api/real-time/\(first)")!
        components.queryItems = [
            URLQueryItem(name: "api_token", value: apiKey),
            URLQueryItem(name: "fmt", value: "json")
        ]
        if symbols.count > 1 {
            components.queryItems?.append(URLQueryItem(name: "s", value: symbols.dropFirst().joined(separator: ",")))
        }
        // A single symbol returns an object, several return an array.
        let quotes: [Quote]
        if symbols.count == 1 {
            quotes = [try await fetch(components.url!)]
        } else {
            quotes = try await fetch(components.url!)
        }
        var result: [String: Double] = [:]
        for quote in quotes {
            if let price = quote.close ?? quote.previousClose, price > 0 {
                result[quote.code] = price
            }
        }
        return result
    }

    private static func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { throw QuoteError.network }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw QuoteError.notFound }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw QuoteError.notFound
        }
    }
}

/// Refreshes prices of all priced holdings and records today's portfolio value.
@MainActor
enum PortfolioPricing {
    private static let lastRefreshKey = "portfolio.lastPriceRefresh"
    private static let refreshInterval: TimeInterval = 6 * 60 * 60

    static var lastRefresh: Date? {
        UserDefaults.standard.object(forKey: lastRefreshKey) as? Date
    }

    /// Updates prices if the last refresh is older than six hours (or `force`).
    /// Returns the new portfolio total if anything changed.
    @discardableResult
    static func refresh(holdings: [Holding], force: Bool = false) async throws -> Double? {
        guard QuoteService.isAvailable else { return nil }
        if !force, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < refreshInterval { return nil }
        let priced = holdings.filter { !$0.symbol.isEmpty && $0.shares > 0 }
        guard !priced.isEmpty else { return nil }

        let prices = try await QuoteService.prices(for: priced.map(\.symbol))
        for holding in priced {
            // The API answers with the code without exchange suffix for some markets.
            let code = holding.symbol
            if let price = prices[code] ?? prices[String(code.split(separator: ".").first ?? "")] {
                holding.applyPrice(price)
            }
        }
        UserDefaults.standard.set(Date.now, forKey: lastRefreshKey)
        return holdings.reduce(0) { $0 + $1.value }
    }
}
