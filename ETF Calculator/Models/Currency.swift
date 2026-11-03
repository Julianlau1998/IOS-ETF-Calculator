//
//  Currency.swift
//  ETF Calculator
//

import SwiftUI

/// Currency choices offered in Settings. An empty code follows the device region.
enum Currency {
    static let storageKey = "currencyCode"
    static let selectable = ["EUR", "USD", "GBP", "CHF", "JPY", "SEK", "NOK", "DKK", "PLN", "CAD", "AUD"]

    static var regionCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    static func resolved(_ stored: String) -> String {
        stored.isEmpty ? regionCode : stored
    }

    static func displayName(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        let symbol = Locale(identifier: Locale.identifier(fromComponents: [
            NSLocale.Key.currencyCode.rawValue: code
        ])).currencySymbol ?? code
        return "\(name) (\(symbol))"
    }
}

extension EnvironmentValues {
    /// ISO currency code used to format all amounts in the app.
    @Entry var currencyCode: String = Currency.regionCode
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
    /// Whole-unit currency for compact display (hero numbers, axis labels).
    static func wholeCurrency(_ code: String) -> FloatingPointFormatStyle<Double>.Currency {
        .currency(code: code).precision(.fractionLength(0))
    }
}

extension Locale {
    /// Symbol for an ISO currency code, e.g. "€" for "EUR".
    func currencySymbol(for code: String) -> String {
        Locale(identifier: Locale.identifier(fromComponents: [
            NSLocale.Key.currencyCode.rawValue: code,
            NSLocale.Key.languageCode.rawValue: language.languageCode?.identifier ?? "en"
        ])).currencySymbol ?? code
    }
}

extension Double {
    /// Locale-correct text for a value given in percent, e.g. 7 → "7%" (en) or "7 %" (de).
    func percentText(_ digits: ClosedRange<Int> = 0...2) -> String {
        (self / 100).formatted(.percent.precision(.fractionLength(digits)))
    }
}

enum NumberStyle {
    /// Whether the current locale puts a space between a number and "%".
    static var percentHasSpace: Bool {
        0.07.formatted(.percent).contains { $0.isWhitespace }
    }

    /// Whether the currency symbol comes before the amount, as in "$10" (en_US).
    static func currencySymbolIsLeading(_ code: String) -> Bool {
        let formatted = 1.0.formatted(.currency(code: code))
        return !(formatted.first?.isNumber ?? true)
    }
}
