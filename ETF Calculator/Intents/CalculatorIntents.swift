//
//  CalculatorIntents.swift
//  ETF Calculator
//

import AppIntents
import Foundation

/// Reads the plan and currency saved by the app, without touching UI state.
private enum SavedPlan {
    static var plan: SavingsPlan {
        guard let data = UserDefaults.standard.data(forKey: "currentPlan"),
              let plan = try? JSONDecoder().decode(SavingsPlan.self, from: data) else { return SavingsPlan() }
        return plan
    }

    static var currency: String {
        Currency.resolved(UserDefaults.standard.string(forKey: Currency.storageKey) ?? "")
    }

    static func format(_ value: Double) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}

/// "How much will I have?" — final value of the saved plan, optionally with other inputs.
struct FinalValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate Final Value"
    static let description = IntentDescription("Calculates the final value of your ETF savings plan.")

    @Parameter(title: "Monthly Contribution")
    var monthlyContribution: Double?

    @Parameter(title: "Years", inclusiveRange: (1, 70))
    var years: Int?

    @Parameter(title: "Expected Return (%)")
    var annualReturn: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Calculate final value") {
            \.$monthlyContribution
            \.$years
            \.$annualReturn
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        var plan = SavedPlan.plan
        if let monthlyContribution { plan.monthlyContribution = max(0, monthlyContribution) }
        if let years { plan.years = min(max(1, years), 70) }
        if let annualReturn { plan.annualReturn = annualReturn }

        let projection = Projection(plan: plan)
        let final = SavedPlan.format(projection.finalValue)
        let monthly = SavedPlan.format(plan.monthlyContribution)
        let gains = SavedPlan.format(projection.totalGains)
        return .result(
            value: projection.finalValue,
            dialog: "Saving \(monthly) per month for \(plan.years) years, you'll have about \(final) — including \(gains) in returns."
        )
    }
}

/// "How much do I need to save?" — monthly contribution required for a target.
struct RequiredSavingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate Required Savings"
    static let description = IntentDescription("Calculates how much you need to save each month to reach a target amount.")

    @Parameter(title: "Target Amount")
    var target: Double

    @Parameter(title: "Years", inclusiveRange: (1, 70))
    var years: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Save for \(\.$target) in \(\.$years) years")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        var plan = SavedPlan.plan
        plan.years = min(max(1, years), 70)
        plan.contributionIncrease = 0
        let monthly = plan.requiredMonthlyContribution(toReach: target) ?? 0
        let monthlyText = SavedPlan.format(monthly)
        let targetText = SavedPlan.format(target)
        return .result(
            value: monthly,
            dialog: "To reach \(targetText) in \(plan.years) years, save about \(monthlyText) per month."
        )
    }
}

struct ETFCalculatorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FinalValueIntent(),
            phrases: [
                "How much will I have with \(.applicationName)",
                "Calculate my final value in \(.applicationName)"
            ],
            shortTitle: "Final Value",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        AppShortcut(
            intent: RequiredSavingsIntent(),
            phrases: [
                "How much do I need to save with \(.applicationName)",
                "Calculate my savings goal in \(.applicationName)"
            ],
            shortTitle: "Savings Goal",
            systemImageName: "flag.checkered"
        )
    }
}
