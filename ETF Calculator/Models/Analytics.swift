//
//  Analytics.swift
//  ETF Calculator
//

import Foundation

// MARK: - Milestones

/// A round amount the portfolio crosses during the savings period.
struct Milestone: Identifiable, Hashable {
    var id: Double { amount }
    let amount: Double
    let year: Int
}

extension Milestone {
    static let roundAmounts: [Double] = [
        10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_500_000, 5_000_000, 10_000_000
    ]
}

/// Consecutive calendar months (up to this or last month) with a recorded value.
enum PortfolioStreak {
    static func months(in dates: [Date], calendar: Calendar = .current, now: Date = .now) -> Int {
        let months = Set(dates.map { calendar.dateComponents([.year, .month], from: $0) })
        guard var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return 0 }
        // A streak is still alive if this month's value isn't recorded yet.
        if !months.contains(calendar.dateComponents([.year, .month], from: cursor)) {
            cursor = calendar.date(byAdding: .month, value: -1, to: cursor) ?? cursor
        }
        var count = 0
        while months.contains(calendar.dateComponents([.year, .month], from: cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

extension Projection {
    private static let milestoneAmounts = Milestone.roundAmounts

    /// The first year in which each round amount is reached, skipping
    /// amounts already exceeded by the initial investment.
    var milestones: [Milestone] {
        Self.milestoneAmounts.compactMap { amount in
            guard plan.initialInvestment < amount,
                  let value = values.first(where: { $0.balance >= amount }) else { return nil }
            return Milestone(amount: amount, year: value.year)
        }
    }
}

// MARK: - Taxes

/// Tax systems the calculator models.
enum TaxRegion: String, CaseIterable, Identifiable {
    case germany, unitedStates, international

    var id: Self { self }

    var name: LocalizedStringResource {
        switch self {
        case .germany: "Germany"
        case .unitedStates: "United States"
        case .international: "International"
        }
    }

    /// Picked from the device region on first launch.
    static var deviceDefault: TaxRegion {
        switch Locale.current.region?.identifier {
        case "DE": .germany
        case "US": .unitedStates
        default: .international
        }
    }
}

/// US account types with very different tax treatment.
enum USAccountType: String, CaseIterable, Identifiable {
    case taxable, roth, traditional

    var id: Self { self }

    var name: LocalizedStringResource {
        switch self {
        case .taxable: "Taxable Brokerage"
        case .roth: "Roth IRA / Roth 401(k)"
        case .traditional: "Traditional IRA / 401(k)"
        }
    }
}

/// Simplified taxes on an ETF savings plan.
///
/// - Germany: 25 % Abgeltungssteuer + 5.5 % Soli = 26.375 %, 30 % Teilfreistellung
///   for equity ETFs, 1,000 € Sparerpauschbetrag and the yearly Vorabpauschale.
/// - United States: long-term capital gains (+ state) for taxable accounts,
///   tax-free Roth, or ordinary income tax on Traditional withdrawals.
/// - International: a flat rate on gains above an optional allowance.
struct TaxSettings: Equatable {
    var region = TaxRegion.deviceDefault
    var isEnabled = true

    // Germany
    var rate = 26.375
    var partialExemption = 30.0
    var allowance = 1_000.0
    /// Taxes the yearly Vorabpauschale instead of only taxing at the end.
    var includesAdvanceLumpSum = true
    /// Basiszins published yearly by the German Federal Ministry of Finance.
    var baseRate = 3.20

    // United States
    var usAccount = USAccountType.taxable
    var usCapitalGainsRate = 15.0
    var usStateRate = 0.0
    var usIncomeRate = 22.0

    // International
    var internationalRate = 20.0
    var internationalAllowance = 0.0

    enum Key {
        static let region = "tax.region"
        static let isEnabled = "tax.enabled"
        static let rate = "tax.rate"
        static let partialExemption = "tax.partialExemption"
        static let allowance = "tax.allowance"
        static let includesAdvanceLumpSum = "tax.advanceLumpSum"
        static let baseRate = "tax.baseRate"
        static let baseRateYear = "tax.baseRateYear"
        static let baseRateAutomatic = "tax.baseRateAutomatic"
        static let usAccount = "tax.usAccount"
        static let usCapitalGainsRate = "tax.usCapitalGainsRate"
        static let usStateRate = "tax.usStateRate"
        static let usIncomeRate = "tax.usIncomeRate"
        static let internationalRate = "tax.internationalRate"
        static let internationalAllowance = "tax.internationalAllowance"
    }

    /// German tax on a gain realized at once (without Vorabpauschale).
    func tax(onGains gains: Double) -> Double {
        let taxable = gains * (1 - partialExemption / 100) - allowance
        return max(0, taxable) * rate / 100
    }
}

/// Taxes over the life of the plan: yearly Vorabpauschale plus the tax on sale.
struct TaxBreakdown {
    struct Year: Identifiable, Hashable {
        var id: Int { year }
        let year: Int
        /// Vorabpauschale (deemed income) for that year.
        let advanceLumpSum: Double
        /// Tax due for that year after allowance.
        let tax: Double
    }

    let years: [Year]
    /// Tax due when selling at the end (gains not yet taxed as Vorabpauschale).
    let finalTax: Double

    var yearlyTaxes: Double { years.reduce(0) { $0 + $1.tax } }
    var total: Double { yearlyTaxes + finalTax }

    func year(_ year: Int) -> Year? { years.first { $0.year == year } }
}

extension Projection {
    /// Average share of a year that monthly deposits (made at the start of
    /// each month) count towards the Vorabpauschale: (12 + 11 + … + 1) / 144.
    private static let averageHoldingShare = 78.0 / 144.0

    func taxBreakdown(_ settings: TaxSettings) -> TaxBreakdown {
        let gains = max(0, totalGains)
        switch settings.region {
        case .germany:
            return germanTaxBreakdown(settings)
        case .unitedStates:
            switch settings.usAccount {
            case .taxable:
                return TaxBreakdown(years: [], finalTax: gains * (settings.usCapitalGainsRate + settings.usStateRate) / 100)
            case .roth:
                return TaxBreakdown(years: [], finalTax: 0)
            case .traditional:
                // Contributions were pre-tax, so the whole withdrawal is taxed as income.
                return TaxBreakdown(years: [], finalTax: finalValue * (settings.usIncomeRate + settings.usStateRate) / 100)
            }
        case .international:
            return TaxBreakdown(years: [], finalTax: max(0, gains - settings.internationalAllowance) * settings.internationalRate / 100)
        }
    }

    private func germanTaxBreakdown(_ settings: TaxSettings) -> TaxBreakdown {
        let exemption = 1 - settings.partialExemption / 100
        let rate = settings.rate / 100
        guard settings.includesAdvanceLumpSum, values.count > 1 else {
            return TaxBreakdown(years: [], finalTax: settings.tax(onGains: max(0, totalGains)))
        }

        var years: [TaxBreakdown.Year] = []
        var taxedLumpSums = 0.0
        for index in 1..<values.count {
            let previous = values[index - 1], current = values[index]
            let deposits = current.contributions - previous.contributions
            let special = plan.isPaused(inYear: current.year) ? 0 : plan.yearlySpecialPayment
            let monthlyDeposits = max(0, deposits - special)
            // Basisertrag: 70 % of the base rate on the value held during the year.
            let baseYield = (previous.balance + monthlyDeposits * Self.averageHoldingShare) * settings.baseRate / 100 * 0.7
            // Capped at the actual increase in value (excluding new money).
            let increase = current.balance - previous.balance - deposits
            let lumpSum = max(0, min(baseYield, increase))
            let tax = max(0, lumpSum * exemption - settings.allowance) * rate
            taxedLumpSums += lumpSum
            years.append(TaxBreakdown.Year(year: current.year, advanceLumpSum: lumpSum, tax: tax))
        }
        // On sale, lump sums already taxed are deducted from the gain.
        let remainingGain = max(0, totalGains - taxedLumpSums)
        let finalTax = max(0, remainingGain * exemption - settings.allowance) * rate
        return TaxBreakdown(years: years, finalTax: finalTax)
    }

    func taxes(_ settings: TaxSettings) -> Double {
        taxBreakdown(settings).total
    }
}

// MARK: - Monte Carlo

/// Percentile bands of simulated portfolio values per year.
struct RangeProjection: Sendable {
    struct Band: Identifiable, Hashable, Sendable {
        var id: Int { year }
        let year: Int
        let low: Double
        let median: Double
        let high: Double
    }

    let bands: [Band]
    /// Share of simulations that end at or above the money paid in.
    let probabilityOfGain: Double

    var final: Band? { bands.last }

    static let simulationCount = 500
    static let volatilityKey = "range.volatility"
    static let defaultVolatility = 15.0

    /// Simulates monthly log-normal returns with the given annual volatility.
    /// A fixed seed keeps results stable while the user edits other values.
    ///
    /// To keep the percentile curves smooth over long horizons:
    /// - paths are simulated in antithetic pairs (each random draw is also used
    ///   mirrored), which cancels much of the sampling noise,
    /// - percentiles are interpolated between neighbouring paths,
    /// - the resulting bands are lightly smoothed in log space (the start and
    ///   the final year, which is shown as numbers, stay unsmoothed).
    init(plan: SavingsPlan, volatility: Double) {
        var generator = SeededGenerator(seed: 0x5EED_E7F)
        let annualRate = (plan.annualReturn - plan.expenseRatio) / 100
        let sigma = volatility / 100 / sqrt(12)
        let drift = log(max(0.0001, 1 + annualRate)) / 12 - sigma * sigma / 2
        let years = max(0, plan.years)

        var valuesPerYear = Array(repeating: [Double](), count: years + 1)
        var finalAboveContributions = 0
        let contributions = Projection(plan: plan).totalContributions

        for _ in 0..<(Self.simulationCount / 2) {
            var balances = (plan.initialInvestment, plan.initialInvestment)
            var monthly = plan.monthlyContribution
            valuesPerYear[0].append(balances.0)
            valuesPerYear[0].append(balances.1)
            for year in stride(from: 1, through: years, by: 1) {
                let paused = plan.isPaused(inYear: year)
                let deposit = paused ? 0 : monthly
                for _ in 0..<12 {
                    let shock = sigma * generator.nextGaussian()
                    balances.0 = (balances.0 + deposit) * exp(drift + shock)
                    balances.1 = (balances.1 + deposit) * exp(drift - shock)
                }
                if !paused {
                    balances.0 += plan.yearlySpecialPayment
                    balances.1 += plan.yearlySpecialPayment
                }
                valuesPerYear[year].append(balances.0)
                valuesPerYear[year].append(balances.1)
                monthly *= 1 + plan.contributionIncrease / 100
            }
            if balances.0 >= contributions { finalAboveContributions += 1 }
            if balances.1 >= contributions { finalAboveContributions += 1 }
        }

        var raw = valuesPerYear.enumerated().map { year, values in
            let sorted = values.sorted()
            return Band(year: year, low: Self.percentile(sorted, 0.1), median: Self.percentile(sorted, 0.5), high: Self.percentile(sorted, 0.9))
        }
        raw = Self.smoothed(raw)
        bands = raw
        probabilityOfGain = Double(finalAboveContributions) / Double(Self.simulationCount)
    }

    /// Linear interpolation between the two nearest ranks.
    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = Double(sorted.count - 1) * p
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Centered moving average in log space; keeps the first and last year exact.
    private static func smoothed(_ bands: [Band], radius: Int = 2) -> [Band] {
        guard bands.count > 4 else { return bands }
        func smooth(_ values: [Double]) -> [Double] {
            let logs = values.map { log(max($0, 1)) }
            return values.indices.map { index in
                guard index > 0, index < values.count - 1 else { return values[index] }
                // Shrink the window near the ends so it stays centered.
                let r = min(radius, index, values.count - 1 - index)
                let window = logs[(index - r)...(index + r)]
                return exp(window.reduce(0, +) / Double(window.count))
            }
        }
        let low = smooth(bands.map(\.low)), median = smooth(bands.map(\.median)), high = smooth(bands.map(\.high))
        return bands.indices.map { Band(year: bands[$0].year, low: low[$0], median: median[$0], high: high[$0]) }
    }
}

/// SplitMix64 – small, fast and deterministic.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    private var spareGaussian: Double?

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Standard normal sample using the Box–Muller transform.
    mutating func nextGaussian() -> Double {
        if let spare = spareGaussian {
            spareGaussian = nil
            return spare
        }
        let u1 = max(Double.random(in: 0..<1, using: &self), .leastNonzeroMagnitude)
        let u2 = Double.random(in: 0..<1, using: &self)
        let radius = sqrt(-2 * log(u1))
        spareGaussian = radius * sin(2 * .pi * u2)
        return radius * cos(2 * .pi * u2)
    }
}

// MARK: - Withdrawal phase

/// Inputs for the payout phase ("Entnahmeplan").
struct PayoutPlan: Equatable {
    var capital: Double = 250_000
    var monthlyWithdrawal: Double = 1_200
    var annualReturn: Double = 4
    /// Yearly increase of the withdrawal, e.g. to offset inflation.
    var withdrawalIncrease: Double = 2

    static let maxYears = 100

    enum Key {
        static let capital = "payout.capital"
        static let withdrawal = "payout.withdrawal"
        static let annualReturn = "payout.return"
        static let increase = "payout.increase"
    }
}

struct PayoutProjection {
    struct Point: Identifiable, Hashable {
        var id: Int { year }
        let year: Int
        let balance: Double
    }

    let plan: PayoutPlan
    let points: [Point]
    /// Months until the capital runs out, `nil` if it lasts `PayoutPlan.maxYears` or longer.
    let monthsUntilDepleted: Int?
    let totalWithdrawn: Double

    /// Monthly amount that can be withdrawn forever without touching the capital.
    var perpetualWithdrawal: Double {
        plan.capital * plan.annualReturn / 100 / 12
    }

    init(plan: PayoutPlan) {
        self.plan = plan
        let monthlyFactor = 1 + plan.annualReturn / 100 / 12
        var balance = plan.capital
        var withdrawal = plan.monthlyWithdrawal
        var withdrawn = 0.0
        var points = [Point(year: 0, balance: balance)]
        var depletedAt: Int?

        months: for year in 1...PayoutPlan.maxYears {
            for month in 1...12 {
                let payout = min(balance, withdrawal)
                withdrawn += payout
                balance = (balance - payout) * monthlyFactor
                if balance <= 0.005 {
                    balance = 0
                    depletedAt = (year - 1) * 12 + month
                    points.append(Point(year: year, balance: 0))
                    break months
                }
            }
            points.append(Point(year: year, balance: balance))
            withdrawal *= 1 + plan.withdrawalIncrease / 100
        }

        self.points = points
        monthsUntilDepleted = depletedAt
        totalWithdrawn = withdrawn
    }
}

// MARK: - CSV export

extension Projection {
    /// Year-by-year table as CSV, using the current locale's decimal separator.
    func csv(currency: String) -> String {
        let separator = Locale.current.decimalSeparator == "," ? ";" : ","
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)).grouping(.never)
        let header = [
            String(localized: "Year"),
            String(localized: "Invested (\(currency))"),
            String(localized: "Returns (\(currency))"),
            String(localized: "Value (\(currency))"),
            String(localized: "In Today's Money (\(currency))")
        ]
        let rows = values.map { value in
            [
                "\(value.year)",
                value.contributions.formatted(number),
                value.gains.formatted(number),
                value.balance.formatted(number),
                value.realBalance.formatted(number)
            ]
        }
        return ([header] + rows).map { $0.joined(separator: separator) }.joined(separator: "\n")
    }
}

// MARK: - Plan vs. actual

extension SavingsPlan {
    /// Planned portfolio value (after costs) and money paid in, a number of months into the plan.
    func plannedState(afterMonths months: Int) -> (value: Double, contributions: Double) {
        let monthlyFactor = 1 + (annualReturn - expenseRatio) / 100 / 12
        var balance = initialInvestment
        var contributions = initialInvestment
        var monthly = monthlyContribution
        guard months > 0 else { return (balance, contributions) }
        for month in 1...months {
            let year = (month - 1) / 12 + 1
            let paused = isPaused(inYear: year)
            let deposit = paused ? 0 : monthly
            balance = (balance + deposit) * monthlyFactor
            contributions += deposit
            if month % 12 == 0 {
                if !paused {
                    balance += yearlySpecialPayment
                    contributions += yearlySpecialPayment
                }
                monthly *= 1 + contributionIncrease / 100
            }
        }
        return (balance, contributions)
    }

    func plannedValue(afterMonths months: Int) -> Double {
        plannedState(afterMonths: months).value
    }

    static func monthsElapsed(from start: Date, to date: Date) -> Int {
        max(0, Calendar.current.dateComponents([.month], from: start, to: date).month ?? 0)
    }

    func plannedValue(at date: Date, startDate: Date) -> Double {
        plannedValue(afterMonths: Self.monthsElapsed(from: startDate, to: date))
    }

    /// Final value if the plan continues from an actual portfolio value today.
    func forecast(fromActual actual: Double, at date: Date, startDate: Date) -> Projection {
        let elapsedMonths = Self.monthsElapsed(from: startDate, to: date)
        let elapsedYears = elapsedMonths / 12
        var remaining = self
        remaining.initialInvestment = actual
        remaining.years = max(1, years - elapsedYears)
        // Contributions have grown with the yearly increase in the meantime.
        remaining.monthlyContribution = monthlyContribution * pow(1 + contributionIncrease / 100, Double(elapsedYears))
        if hasPause {
            remaining.pauseStartYear = max(0, pauseStartYear - elapsedYears)
        }
        return Projection(plan: remaining)
    }
}
