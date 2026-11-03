//
//  AppGroup.swift
//  ETF Calculator
//
//  Shared between the app and the widget extension.
//

import Foundation

/// Storage shared with the widget extension.
enum AppGroup {
    static let identifier = "group.app.etf-calculator.com"

    /// Falls back to standard defaults if the App Group isn't provisioned.
    static let defaults = UserDefaults(suiteName: identifier) ?? .standard

    enum Key {
        static let isPremium = "isPremium"
        static let snapshot = "widgetSnapshot"
    }
}

/// Everything the widgets need, precomputed by the app.
struct WidgetSnapshot: Codable, Hashable {
    struct Point: Codable, Hashable {
        let year: Int
        let value: Double
    }

    var finalValue: Double
    var totalContributions: Double
    var years: Int
    var monthlyContribution: Double
    var currencyCode: String
    var points: [Point]
    /// Next round amount the plan reaches and the calendar year it happens.
    var nextMilestone: Double?
    var nextMilestoneYear: Int?
    /// Savings goal progress (0…1) based on the plan's value today, if a goal is set.
    var goalTarget: Double?
    var goalProgress: Double?
    var updatedAt: Date

    var gains: Double { finalValue - totalContributions }

    static let placeholder = WidgetSnapshot(
        finalValue: 19_186,
        totalContributions: 13_000,
        years: 10,
        monthlyContribution: 100,
        currencyCode: Locale.current.currency?.identifier ?? "EUR",
        points: (0...10).map { Point(year: $0, value: 1_000 + Double($0) * 1_200 * pow(1.035, Double($0))) },
        nextMilestone: 10_000,
        nextMilestoneYear: Calendar.current.component(.year, from: .now) + 6,
        goalTarget: 100_000,
        goalProgress: 0.32,
        updatedAt: .now
    )

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.Key.snapshot) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults.set(data, forKey: AppGroup.Key.snapshot)
    }
}
