//
//  DemoData.swift
//  ETF Calculator
//
//  Debug only: realistic sample data for App Store screenshots.
//  Launch with `-screenshotDemo` to load it.
//

#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DemoData {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotDemo")
    }

    /// Replaces the stored data with a consistent example portfolio.
    static func seed(context: ModelContext, calculator: CalculatorModel) {
        try? context.delete(model: Scenario.self)
        try? context.delete(model: PortfolioEntry.self)
        try? context.delete(model: Holding.self)
        try? context.delete(model: Dividend.self)

        let calendar = Calendar.current
        func monthsAgo(_ months: Int) -> Date { calendar.date(byAdding: .month, value: -months, to: .now) ?? .now }

        // Calculator
        calculator.plan = SavingsPlan(
            initialInvestment: 10_000,
            monthlyContribution: 500,
            years: 30,
            annualReturn: 7,
            contributionIncrease: 2,
            expenseRatio: 0.2,
            inflation: 2
        )

        // Scenarios to compare
        context.insert(Scenario(name: String(localized: "Balanced"), plan: SavingsPlan(initialInvestment: 10_000, monthlyContribution: 500, years: 30, annualReturn: 6), createdAt: monthsAgo(1)))
        context.insert(Scenario(name: String(localized: "World ETF"), plan: SavingsPlan(initialInvestment: 10_000, monthlyContribution: 500, years: 30, annualReturn: 7), createdAt: monthsAgo(2)))
        context.insert(Scenario(name: String(localized: "Optimistic"), plan: SavingsPlan(initialInvestment: 10_000, monthlyContribution: 750, years: 30, annualReturn: 9), createdAt: monthsAgo(3)))

        // Real savings plan, started 3 years ago
        let start = monthsAgo(36)
        calculator.planStartDate = start
        calculator.portfolioPlan = SavingsPlan(initialInvestment: 5_000, monthlyContribution: 500, years: 30, annualReturn: 7, contributionIncrease: 0, expenseRatio: 0.2, inflation: 2)

        // Recorded values: slightly ahead of plan with some ups and downs
        let wiggle: [Double] = [1.00, 0.97, 1.02, 1.05, 0.99, 1.04, 1.08, 1.03, 1.06, 1.10, 1.07, 1.09, 1.12]
        for (index, factor) in wiggle.enumerated() {
            let months = index * 3
            let planned = calculator.portfolioPlan!.plannedValue(afterMonths: months)
            context.insert(PortfolioEntry(date: calendar.date(byAdding: .month, value: months, to: start) ?? start, value: (planned * factor).rounded()))
        }

        // Positions
        let positions: [(String, String, Double, Double, Double, Double, AssetClass, Double)] = [
            ("Vanguard FTSE All-World", "IE00BK5BQT80", 152, 128.40, 16_420, 0.22, .world, 60),
            ("iShares Core S&P 500", "IE00B5BMR087", 9.5, 612.30, 4_980, 0.07, .usa, 20),
            ("Xtrackers MSCI Emerging Markets", "IE00BTJRMP35", 41, 58.20, 2_210, 0.18, .emergingMarkets, 10),
            ("iShares Global Aggregate Bond", "IE00B3F81409", 330, 5.42, 1_760, 0.10, .bonds, 10)
        ]
        for (index, position) in positions.enumerated() {
            let holding = Holding(name: position.0, value: position.2 * position.3, colorIndex: index)
            holding.isin = position.1
            holding.shares = position.2
            holding.price = position.3
            holding.costBasis = position.4
            holding.expenseRatio = position.5
            holding.assetClass = position.6
            holding.targetWeight = position.7
            holding.priceUpdatedAt = .now
            context.insert(holding)
        }

        // Dividends over the last year
        for months in [2, 5, 8, 11] {
            context.insert(Dividend(date: monthsAgo(months), amount: [86.40, 92.15, 78.90, 95.30][months / 3], note: "Vanguard FTSE All-World"))
        }

        try? context.save()
    }

    /// The screen a screenshot run opens: `-screenshotScreen plan`
    /// (calculator, plan, yearly, goal, payout, portfolio, allocation, scenarios, paywall, plans).
    static var screen: String? {
        isRequested ? UserDefaults.standard.string(forKey: "screenshotScreen") : nil
    }

    static var tab: AppTab {
        switch screen {
        case "goal": .goal
        case "payout": .payout
        case "portfolio", "allocation": .portfolio
        case "scenarios": .scenarios
        default: .calculator
        }
    }
}
#endif

import SwiftUI

extension View {
    /// Screenshot runs: scrolls the form to the section whose `id` matches `-screenshotScreen`.
    /// Does nothing in release builds.
    func screenshotScrollTarget() -> some View {
        #if DEBUG
        ScrollViewReader { proxy in
            self.task {
                guard let screen = DemoData.screen else { return }
                // Wait for the seeded data to lay out before scrolling.
                try? await Task.sleep(for: .seconds(1.5))
                // Slightly below the top, so the section header clears the navigation bar.
                proxy.scrollTo(screen, anchor: UnitPoint(x: 0.5, y: 0.12))
            }
        }
        #else
        self
        #endif
    }
}
