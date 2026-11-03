//
//  WidgetSync.swift
//  ETF Calculator
//

import Foundation
import WidgetKit

/// Writes the data shown by the widgets and asks WidgetKit to refresh.
enum WidgetSync {
    static func update(
        plan: SavingsPlan,
        currency: String,
        planStartDate: Date?,
        latestPortfolioValue: Double?,
        goalTarget: Double?
    ) {
        let projection = Projection(plan: plan)
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: .now)
        let startYear = planStartDate.map { calendar.component(.year, from: $0) } ?? currentYear

        // The next milestone that still lies in the future.
        let upcoming = projection.milestones.first { startYear + $0.year >= currentYear }

        // Progress towards the savings goal: actual value if recorded, otherwise the plan.
        var progress: Double?
        if let goalTarget, goalTarget > 0 {
            let current = latestPortfolioValue
                ?? planStartDate.map { plan.plannedValue(at: .now, startDate: $0) }
                ?? plan.initialInvestment
            progress = current / goalTarget
        }

        let snapshot = WidgetSnapshot(
            finalValue: projection.finalValue,
            totalContributions: projection.totalContributions,
            years: plan.years,
            monthlyContribution: plan.monthlyContribution,
            currencyCode: currency,
            points: projection.values.map { WidgetSnapshot.Point(year: $0.year, value: $0.balance) },
            nextMilestone: upcoming?.amount,
            nextMilestoneYear: upcoming.map { startYear + $0.year },
            goalTarget: goalTarget,
            goalProgress: progress,
            updatedAt: .now
        )
        guard snapshot.withoutTimestamp != WidgetSnapshot.load()?.withoutTimestamp else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func premiumChanged(_ isPremium: Bool) {
        AppGroup.defaults.set(isPremium, forKey: AppGroup.Key.isPremium)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension WidgetSnapshot {
    /// Used to skip redundant widget reloads.
    var withoutTimestamp: WidgetSnapshot {
        var copy = self
        copy.updatedAt = .distantPast
        return copy
    }
}
