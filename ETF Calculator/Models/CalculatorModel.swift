//
//  CalculatorModel.swift
//  ETF Calculator
//

import Foundation
import Observation

/// Holds the plan currently edited in the calculator and persists it
/// between launches so people pick up where they left off.
@Observable
@MainActor
final class CalculatorModel {
    private static let storageKey = "currentPlan"

    var plan: SavingsPlan {
        didSet { save() }
    }

    var projection: Projection { Projection(plan: plan) }

    /// When the user's real savings plan started (for comparing "My Portfolio").
    var planStartDate: Date? = UserDefaults.standard.object(forKey: "planStartDate") as? Date {
        didSet { UserDefaults.standard.set(planStartDate, forKey: "planStartDate") }
    }

    /// The user's real savings plan, set up explicitly in "My Portfolio".
    /// Kept separate from `plan` so the calculator stays free for playing around.
    var portfolioPlan: SavingsPlan? = CalculatorModel.loadPortfolioPlan() {
        didSet {
            if let portfolioPlan, let data = try? JSONEncoder().encode(portfolioPlan) {
                UserDefaults.standard.set(data, forKey: "portfolioPlan")
            } else {
                UserDefaults.standard.removeObject(forKey: "portfolioPlan")
            }
        }
    }

    /// Typical monthly purchase amount found in the last broker import.
    var suggestedMonthlyContribution: Double? = UserDefaults.standard.object(forKey: "portfolio.suggestedMonthly") as? Double {
        didSet { UserDefaults.standard.set(suggestedMonthlyContribution, forKey: "portfolio.suggestedMonthly") }
    }

    /// Plan and start date for the portfolio comparison, if set up.
    var portfolioComparisonPlan: (plan: SavingsPlan, start: Date)? {
        guard let portfolioPlan, let planStartDate else { return nil }
        return (portfolioPlan, planStartDate)
    }

    private static func loadPortfolioPlan() -> SavingsPlan? {
        guard let data = UserDefaults.standard.data(forKey: "portfolioPlan") else { return nil }
        return try? JSONDecoder().decode(SavingsPlan.self, from: data)
    }

    /// Last Monte Carlo result; simulations are comparatively expensive,
    /// so they're only recomputed when plan or volatility change.
    @ObservationIgnored private var cachedRange: (plan: SavingsPlan, volatility: Double, result: RangeProjection)?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(SavingsPlan.self, from: data) {
            plan = stored
        } else {
            plan = SavingsPlan()
        }
    }

    func range(volatility: Double) -> RangeProjection {
        if let cachedRange, cachedRange.plan == plan, cachedRange.volatility == volatility {
            return cachedRange.result
        }
        let result = RangeProjection(plan: plan, volatility: volatility)
        cachedRange = (plan, volatility, result)
        return result
    }

    func reset() {
        plan = SavingsPlan()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
