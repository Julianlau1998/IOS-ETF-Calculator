//
//  SavingsPlan.swift
//  ETF Calculator
//

import Foundation

/// The user-editable inputs of an ETF savings plan.
struct SavingsPlan: Codable, Hashable, Sendable {
    /// One-off investment at the start.
    var initialInvestment: Double = 1_000
    /// Contribution invested at the beginning of every month.
    var monthlyContribution: Double = 100
    /// Investment horizon in whole years.
    var years: Int = 10
    /// Expected average annual return in percent (before costs).
    var annualReturn: Double = 7
    /// Yearly increase of the monthly contribution in percent ("Dynamik").
    var contributionIncrease: Double = 0
    /// Total expense ratio of the fund in percent per year.
    var expenseRatio: Double = 0.2
    /// Expected average inflation in percent per year.
    var inflation: Double = 2
    /// One-off payment invested at the end of every year (e.g. a bonus).
    var yearlySpecialPayment: Double = 0
    /// First year without contributions (1-based); `0` means no pause.
    var pauseStartYear: Int = 0
    /// Number of years without contributions, starting at `pauseStartYear`.
    var pauseLength: Int = 0

    static let yearsRange = 1...70
    static let returnRange = 0.0...30.0

    /// Whether contributions are paused in the given (1-based) year.
    func isPaused(inYear year: Int) -> Bool {
        pauseStartYear > 0 && pauseLength > 0 && (pauseStartYear..<pauseStartYear + pauseLength).contains(year)
    }

    var hasPause: Bool { pauseStartYear > 0 && pauseLength > 0 }
}

extension SavingsPlan {
    private enum CodingKeys: String, CodingKey {
        case initialInvestment, monthlyContribution, years, annualReturn, contributionIncrease
        case expenseRatio, inflation, yearlySpecialPayment, pauseStartYear, pauseLength
    }

    /// Tolerates data saved by older versions that lack newer fields.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SavingsPlan()
        initialInvestment = try container.decodeIfPresent(Double.self, forKey: .initialInvestment) ?? defaults.initialInvestment
        monthlyContribution = try container.decodeIfPresent(Double.self, forKey: .monthlyContribution) ?? defaults.monthlyContribution
        years = try container.decodeIfPresent(Int.self, forKey: .years) ?? defaults.years
        annualReturn = try container.decodeIfPresent(Double.self, forKey: .annualReturn) ?? defaults.annualReturn
        contributionIncrease = try container.decodeIfPresent(Double.self, forKey: .contributionIncrease) ?? defaults.contributionIncrease
        expenseRatio = try container.decodeIfPresent(Double.self, forKey: .expenseRatio) ?? defaults.expenseRatio
        inflation = try container.decodeIfPresent(Double.self, forKey: .inflation) ?? defaults.inflation
        yearlySpecialPayment = try container.decodeIfPresent(Double.self, forKey: .yearlySpecialPayment) ?? 0
        pauseStartYear = try container.decodeIfPresent(Int.self, forKey: .pauseStartYear) ?? 0
        pauseLength = try container.decodeIfPresent(Int.self, forKey: .pauseLength) ?? 0
    }
}

/// A single data point of the projection (end of a year).
struct YearlyValue: Identifiable, Hashable, Sendable {
    var id: Int { year }
    let year: Int
    /// Total amount the investor paid in so far.
    let contributions: Double
    /// Portfolio value after costs.
    let balance: Double
    /// Portfolio value in today's purchasing power.
    let realBalance: Double

    var gains: Double { balance - contributions }
}

/// The result of running a `SavingsPlan` through the compound-interest engine.
struct Projection: Sendable {
    let plan: SavingsPlan
    let values: [YearlyValue]
    /// Fees paid over the whole period (difference to a cost-free fund).
    let totalCosts: Double

    var finalValue: Double { values.last?.balance ?? 0 }
    var totalContributions: Double { values.last?.contributions ?? 0 }
    var totalGains: Double { finalValue - totalContributions }
    var realFinalValue: Double { values.last?.realBalance ?? 0 }

    /// Gains as a share of the final value, between 0 and 1.
    var gainShare: Double {
        finalValue > 0 ? max(0, totalGains) / finalValue : 0
    }

    init(plan: SavingsPlan) {
        self.plan = plan
        let net = Self.simulate(plan, applyingCosts: true)
        let gross = Self.simulate(plan, applyingCosts: false)
        values = net
        totalCosts = max(0, (gross.last?.balance ?? 0) - (net.last?.balance ?? 0))
    }

    /// Monthly compounding: each month the contribution is invested first,
    /// then the whole balance grows by the monthly rate (matches the web app).
    private static func simulate(_ plan: SavingsPlan, applyingCosts: Bool) -> [YearlyValue] {
        let annualRate = plan.annualReturn - (applyingCosts ? plan.expenseRatio : 0)
        let monthlyFactor = 1 + annualRate / 100 / 12
        let inflationFactor = 1 + plan.inflation / 100

        var balance = plan.initialInvestment
        var contributions = plan.initialInvestment
        var monthly = plan.monthlyContribution
        var values = [YearlyValue(year: 0, contributions: contributions, balance: balance, realBalance: balance)]

        guard plan.years > 0 else { return values }
        for year in 1...plan.years {
            let paused = plan.isPaused(inYear: year)
            let deposit = paused ? 0 : monthly
            for _ in 0..<12 {
                balance = (balance + deposit) * monthlyFactor
                contributions += deposit
            }
            if !paused {
                balance += plan.yearlySpecialPayment
                contributions += plan.yearlySpecialPayment
            }
            let real = balance / pow(inflationFactor, Double(year))
            values.append(YearlyValue(year: year, contributions: contributions, balance: balance, realBalance: real))
            monthly *= 1 + plan.contributionIncrease / 100
        }
        return values
    }
}

extension SavingsPlan {
    /// Solves for the monthly contribution required to reach `target`.
    ///
    /// The final value is linear in the monthly contribution, so two
    /// evaluations are enough to solve it exactly. Returns `0` if the initial
    /// investment alone reaches the target, and `nil` if contributions
    /// can't grow the portfolio (e.g. a horizon of zero years).
    func requiredMonthlyContribution(toReach target: Double) -> Double? {
        var withoutContributions = self
        withoutContributions.monthlyContribution = 0
        var withUnitContribution = self
        withUnitContribution.monthlyContribution = 1

        let base = Projection(plan: withoutContributions).finalValue
        let slope = Projection(plan: withUnitContribution).finalValue - base
        guard slope > 0 else { return nil }
        return max(0, (target - base) / slope)
    }
}
