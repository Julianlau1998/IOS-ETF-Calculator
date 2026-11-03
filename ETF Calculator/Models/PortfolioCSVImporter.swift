//
//  PortfolioCSVImporter.swift
//  ETF Calculator
//

import Foundation

/// Reads portfolio overviews exported by brokers and banks (comdirect, ING,
/// DKB, consorsbank, Scalable, flatex, Fidelity, Schwab, …).
///
/// Exports differ in delimiter, encoding, preamble lines and column names,
/// so the importer looks for a header row with familiar column names and
/// parses numbers in both German ("1.234,56") and English ("1,234.56") style.
enum PortfolioCSVImporter {
    struct Position: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var isin: String
        var symbol: String
        var shares: Double
        var price: Double
        var value: Double
        /// Amount actually paid (incl. fees), 0 if the file doesn't say.
        var costBasis: Double = 0
    }

    struct ImportedDividend: Hashable {
        let date: Date
        let amount: Double
        let note: String
    }

    struct Result {
        var positions: [Position]
        var dividends: [ImportedDividend] = []
        /// Built from a transaction history (e.g. Trade Republic) instead of a
        /// portfolio overview; values are based on the last execution prices.
        var isFromTransactions = false
        /// Date of the first purchase in a transaction history.
        var firstTransactionDate: Date?
        /// Typical (median) amount bought per month, e.g. the savings plan rate.
        var typicalMonthlyPurchase: Double?

        var totalCostBasis: Double { positions.reduce(0) { $0 + $1.costBasis } }
    }

    enum ImportError: LocalizedError {
        case unreadable, noHeader, noPositions

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "The file couldn't be read.")
            case .noHeader: String(localized: "No portfolio table was found. Export the portfolio overview from your broker as CSV.")
            case .noPositions: String(localized: "The file contains no positions with a value.")
            }
        }
    }

    private enum Column { case isin, name, symbol, shares, price, value, type, date, amount, fee, costTotal, costPerShare }

    private static let isinPattern = #"^[A-Z]{2}[A-Z0-9]{9}[0-9]$"#

    static func parse(_ data: Data) throws -> Result {
        guard let content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1) else { throw ImportError.unreadable }

        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let delimiter = detectDelimiter(lines)

        // Find the header among the first lines (exports often start with a preamble).
        var header: [Column: Int] = [:]
        var headerIndex: Int?
        for (index, line) in lines.prefix(40).enumerated() {
            let columns = mapColumns(fields(of: line, delimiter: delimiter))
            let hasIdentifier = columns[.isin] != nil || columns[.name] != nil || columns[.symbol] != nil
            let isOverview = columns[.value] != nil || (columns[.shares] != nil && columns[.price] != nil)
            let isTransactions = columns[.type] != nil && columns[.shares] != nil
            if hasIdentifier, isOverview || isTransactions {
                header = columns
                headerIndex = index
                break
            }
        }
        guard let headerIndex else { throw ImportError.noHeader }

        let rows = lines.dropFirst(headerIndex + 1)
            .map { fields(of: $0, delimiter: delimiter) }
            .filter { $0.count > 1 }
        let decimalComma = detectDecimalComma(rows)

        func text(_ column: Column, in row: [String]) -> String {
            guard let index = header[column], index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespaces)
        }
        func number(_ column: Column, in row: [String]) -> Double {
            parseNumber(text(column, in: row), preferDecimalComma: decimalComma) ?? 0
        }
        func identifier(in row: [String]) -> String? {
            let candidates = [text(.isin, in: row), text(.symbol, in: row)].map { $0.uppercased() }
            return candidates.first { $0.range(of: isinPattern, options: .regularExpression) != nil }
        }

        if header[.type] != nil, header[.value] == nil {
            return try transactions(rows: rows, text: text, number: number, identifier: identifier)
        }

        var positions: [Position] = []
        for row in rows {
            let isin = identifier(in: row)
            let name = text(.name, in: row).isEmpty ? text(.symbol, in: row) : text(.name, in: row)
            let shares = number(.shares, in: row)
            let price = number(.price, in: row)
            var value = number(.value, in: row)
            if value == 0, shares > 0, price > 0 { value = shares * price }

            guard value > 0, isin != nil || !name.isEmpty else { continue }
            // Skip summary rows such as "Summe" / "Account Total".
            let lowered = name.lowercased()
            if isin == nil {
                if ["summe", "gesamt", "total", "depotwert", "account total", "cash"].contains(where: lowered.hasPrefix) { continue }
                // A row without shares in a table that has a shares column is a subtotal.
                if header[.shares] != nil, shares == 0 { continue }
            }

            var costBasis = number(.costTotal, in: row)
            if costBasis == 0, shares > 0 { costBasis = number(.costPerShare, in: row) * shares }

            positions.append(Position(
                name: name.isEmpty ? (isin ?? "") : name,
                isin: isin ?? "",
                symbol: isin == nil ? text(.symbol, in: row).uppercased() : "",
                shares: shares,
                price: price,
                value: value,
                costBasis: costBasis
            ))
        }
        guard !positions.isEmpty else { throw ImportError.noPositions }
        return Result(positions: positions)
    }

    /// Aggregates a transaction history into current positions:
    /// buys and savings plan executions add shares, sells (negative shares
    /// or a sell type) remove them; dividends are collected separately.
    private static func transactions(
        rows: [[String]],
        text: (Column, [String]) -> String,
        number: (Column, [String]) -> Double,
        identifier: ([String]) -> String?
    ) throws -> Result {
        struct Aggregate {
            var name = ""
            var shares = 0.0
            var lastPrice = 0.0
            var lastDate = Date.distantPast
            /// Average-cost method: buys add what was paid, sells remove the average cost.
            var costBasis = 0.0
        }
        var firstPurchase: Date?
        var purchasesPerMonth: [DateComponents: Double] = [:]
        var aggregates: [String: Aggregate] = [:]
        var dividends: [ImportedDividend] = []

        for (index, row) in rows.enumerated() {
            let type = text(.type, row).lowercased()
            let date = parseDate(text(.date, row)) ?? Date(timeIntervalSince1970: TimeInterval(index))
            let amount = number(.amount, row)
            let name = text(.name, row)

            if ["dividend", "dividende", "distribution", "ausschüttung", "ausschuettung"].contains(where: type.contains) {
                if amount > 0 { dividends.append(ImportedDividend(date: date, amount: amount, note: name)) }
                continue
            }

            guard let isin = identifier(row) else { continue }
            var shares = number(.shares, row)
            guard shares != 0 else { continue }
            let isSell = ["sell", "verkauf", "sale"].contains(where: type.contains)
            if isSell, shares > 0 { shares = -shares }

            var price = number(.price, row)
            if price <= 0, amount != 0 { price = abs(amount) / abs(shares) }

            var aggregate = aggregates[isin] ?? Aggregate()
            if shares > 0 {
                let paid = amount != 0 ? abs(amount) : shares * price
                aggregate.costBasis += paid + abs(number(.fee, row))
                firstPurchase = min(firstPurchase ?? date, date)
                purchasesPerMonth[Calendar.current.dateComponents([.year, .month], from: date), default: 0] += paid
            } else if aggregate.shares > 0 {
                let averageCost = aggregate.costBasis / aggregate.shares
                aggregate.costBasis = max(0, aggregate.costBasis - averageCost * min(-shares, aggregate.shares))
            }
            aggregate.shares += shares
            if !name.isEmpty { aggregate.name = name }
            if price > 0, date >= aggregate.lastDate {
                aggregate.lastPrice = price
                aggregate.lastDate = date
            }
            aggregates[isin] = aggregate
        }

        let positions = aggregates
            .filter { $0.value.shares > 0.000_1 }
            .map { isin, aggregate in
                Position(
                    name: aggregate.name.isEmpty ? isin : aggregate.name,
                    isin: isin,
                    symbol: "",
                    shares: aggregate.shares,
                    price: aggregate.lastPrice,
                    value: aggregate.shares * aggregate.lastPrice,
                    costBasis: aggregate.costBasis
                )
            }
            .sorted { $0.value > $1.value }
        guard !positions.isEmpty else { throw ImportError.noPositions }
        let monthlyTotals = purchasesPerMonth.values.sorted()
        let median = monthlyTotals.isEmpty ? nil : monthlyTotals[monthlyTotals.count / 2]
        return Result(
            positions: positions,
            dividends: dividends,
            isFromTransactions: true,
            firstTransactionDate: firstPurchase,
            typicalMonthlyPurchase: median.map { ($0 / 5).rounded() * 5 }
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "MM/dd/yyyy", "yyyy-MM-dd'T'HH:mm:ss", "dd.MM.yyyy HH:mm"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: String(text.prefix(format.count + 2)).trimmingCharacters(in: .whitespaces)) { return date }
        }
        return nil
    }

    /// Looks at the numbers in the file to decide whether "," is the decimal separator.
    private static func detectDecimalComma(_ rows: [[String]]) -> Bool {
        var comma = 0, dot = 0
        for field in rows.prefix(200).joined() {
            let value = field.trimmingCharacters(in: .whitespaces)
            if value.range(of: #"^-?[\d.]*\d,\d{1,2}$"#, options: .regularExpression) != nil { comma += 1 }
            if value.range(of: #"^-?[\d,]*\d\.\d+$"#, options: .regularExpression) != nil,
               value.range(of: #"^-?\d{1,3}(\.\d{3})+$"#, options: .regularExpression) == nil { dot += 1 }
        }
        return comma > dot
    }

    // MARK: Parsing helpers

    private static func detectDelimiter(_ lines: [String]) -> Character {
        let sample = lines.prefix(40).joined(separator: "\n")
        let candidates: [Character] = [";", ",", "\t"]
        return candidates.max { a, b in sample.filter { $0 == a }.count < sample.filter { $0 == b }.count } ?? ";"
    }

    /// Splits a CSV line, honoring quotes ("a;b" stays one field).
    static func fields(of line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                isQuoted.toggle()
            } else if character == delimiter, !isQuoted {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
    }

    private static func mapColumns(_ titles: [String]) -> [Column: Int] {
        var columns: [Column: Int] = [:]
        for (index, raw) in titles.enumerated() {
            let title = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            // Order matters: "kurswert" must count as value, not price.
            if title == "type" || title == "typ" {
                // Prefer an explicit type column over "category".
                columns[.type] = index
            } else if columns[.isin] == nil, title.contains("isin") {
                columns[.isin] = index
            } else if columns[.type] == nil, ["type", "typ", "transaktion", "transaction", "buchungsart", "category", "kategorie"].contains(title) {
                columns[.type] = index
            } else if columns[.date] == nil, ["datetime", "date", "datum", "buchungstag", "trade date"].contains(title) {
                columns[.date] = index
            } else if columns[.amount] == nil, ["amount", "betrag", "betrag (eur)", "amount (eur)"].contains(title) {
                columns[.amount] = index
            } else if columns[.fee] == nil, ["fee", "fees", "gebühr", "gebühren", "provision"].contains(title) {
                columns[.fee] = index
            } else if columns[.costTotal] == nil, ["einstandswert", "kaufwert", "anschaffungswert", "kostenbasis", "cost basis", "total cost", "einstand"].contains(where: title.contains) {
                columns[.costTotal] = index
            } else if columns[.costPerShare] == nil, ["einstandskurs", "kaufkurs", "durchschnittskurs", "average cost", "avg cost", "avg. cost"].contains(where: title.contains) {
                columns[.costPerShare] = index
            } else if columns[.value] == nil, isValueTitle(title) {
                columns[.value] = index
            } else if columns[.shares] == nil, ["stück", "stueck", "stk", "anzahl", "menge", "nominal", "bestand", "quantity", "shares", "units", "qty"].contains(where: title.contains) {
                columns[.shares] = index
            } else if columns[.price] == nil, ["kurs", "preis", "price", "last"].contains(where: title.contains) {
                columns[.price] = index
            } else if columns[.name] == nil, ["bezeichnung", "name", "wertpapier", "titel", "description", "security", "instrument", "produkt"].contains(where: title.contains) {
                columns[.name] = index
            } else if columns[.symbol] == nil, ["symbol", "ticker", "wkn"].contains(where: title.contains) {
                columns[.symbol] = index
            }
        }
        return columns
    }

    /// "Kurswert", "Wert in EUR", "Market Value" … but not "Wertpapier".
    private static func isValueTitle(_ title: String) -> Bool {
        let specific = ["kurswert", "marktwert", "wert in", "gesamtwert", "depotwert", "positionswert", "market value", "current value", "total value"]
        if specific.contains(where: title.contains) { return true }
        let generic = ["wert", "value", "betrag", "wert (eur)", "wert eur", "value (usd)"]
        return generic.contains(title) || title.hasPrefix("wert ") || title.hasPrefix("value ")
    }

    /// Parses "1.234,56 €", "1,234.56", "-12,5" … into a number.
    static func parseNumber(_ text: String, preferDecimalComma: Bool) -> Double? {
        var cleaned = text.filter { "0123456789,.-".contains($0) }
        guard !cleaned.isEmpty else { return nil }
        let lastComma = cleaned.lastIndex(of: ",")
        let lastDot = cleaned.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            if comma > dot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        case (_?, nil):
            // "1,234" is ambiguous: German exports use the comma as decimal separator.
            let looksLikeThousands = cleaned.range(of: #"^-?\d{1,3}(,\d{3})+$"#, options: .regularExpression) != nil
            cleaned = looksLikeThousands && !preferDecimalComma
                ? cleaned.replacingOccurrences(of: ",", with: "")
                : cleaned.replacingOccurrences(of: ",", with: ".")
        case (nil, _?):
            let looksLikeThousands = cleaned.range(of: #"^-?\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil
            if looksLikeThousands && preferDecimalComma {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
            }
        case (nil, nil):
            break
        }
        return Double(cleaned)
    }
}
