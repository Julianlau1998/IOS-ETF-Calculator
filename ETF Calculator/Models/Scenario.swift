//
//  Scenario.swift
//  ETF Calculator
//

import Foundation
import SwiftData

/// A savings plan the user saved for later reference and comparison.
/// All properties have defaults so the model can sync via CloudKit.
@Model
final class Scenario {
    var name: String = ""
    var createdAt: Date = Date.now
    var plan: SavingsPlan = SavingsPlan()

    init(name: String, plan: SavingsPlan, createdAt: Date = .now) {
        self.name = name
        self.plan = plan
        self.createdAt = createdAt
    }
}

/// An actual portfolio value the user recorded ("Mein Depot").
@Model
final class PortfolioEntry {
    var date: Date = Date.now
    var value: Double = 0

    init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Broad asset classes for the allocation chart.
enum AssetClass: String, CaseIterable, Identifiable {
    case world, usa, europe, emergingMarkets, smallCaps, bonds, realEstate, commodities, cash, other

    var id: Self { self }

    var name: LocalizedStringResource {
        switch self {
        case .world: "World Equities"
        case .usa: "US Equities"
        case .europe: "European Equities"
        case .emergingMarkets: "Emerging Markets"
        case .smallCaps: "Small Caps"
        case .bonds: "Bonds"
        case .realEstate: "Real Estate"
        case .commodities: "Commodities & Gold"
        case .cash: "Cash"
        case .other: "Other"
        }
    }
}

/// A position in the user's portfolio, e.g. "MSCI World" (Premium).
/// Either a manual value, or shares × price (price updated automatically if available).
@Model
final class Holding {
    var name: String = ""
    var value: Double = 0
    var colorIndex: Int = 0
    var createdAt: Date = Date.now
    var isin: String = ""
    /// Exchange symbol used by the quote service, e.g. "EUNL.XETRA".
    var symbol: String = ""
    var shares: Double = 0
    var price: Double = 0
    var priceUpdatedAt: Date?
    /// Total expense ratio in percent.
    var expenseRatio: Double = 0
    var assetClassRaw: String = AssetClass.world.rawValue
    /// Target share of the portfolio in percent (0 = none).
    var targetWeight: Double = 0
    /// What was actually paid for the position (incl. fees); 0 if unknown.
    var costBasis: Double = 0

    var assetClass: AssetClass {
        get { AssetClass(rawValue: assetClassRaw) ?? .other }
        set { assetClassRaw = newValue.rawValue }
    }

    /// Whether the value is derived from shares and price.
    var isPriced: Bool { shares > 0 && price > 0 }

    init(name: String, value: Double, colorIndex: Int) {
        self.name = name
        self.value = value
        self.colorIndex = colorIndex
    }

    /// Recomputes `value` from shares and price, if both are known.
    func applyPrice(_ newPrice: Double, at date: Date = .now) {
        price = newPrice
        priceUpdatedAt = date
        if shares > 0 { value = shares * newPrice }
    }
}

/// A dividend or distribution received (Premium).
@Model
final class Dividend {
    var date: Date = Date.now
    var amount: Double = 0
    var note: String = ""

    init(date: Date, amount: Double, note: String) {
        self.date = date
        self.amount = amount
        self.note = note
    }
}

enum DataStore {
    static let models: [any PersistentModel.Type] = [Scenario.self, PortfolioEntry.self, Holding.self, Dividend.self]

    /// Syncs through the user's private iCloud database when available.
    /// If the store can't be opened (e.g. an incompatible pre-release
    /// schema), it falls back to a fresh local store instead of crashing.
    static func makeContainer() -> ModelContainer {
        let schema = Schema(models)
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            return container
        }
        let local = ModelConfiguration(schema: schema, url: URL.applicationSupportDirectory.appending(path: "Local.store"), cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }
        // Last resort keeps the app usable; data won't persist this session.
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
