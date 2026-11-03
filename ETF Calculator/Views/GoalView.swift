//
//  GoalView.swift
//  ETF Calculator
//

import SwiftUI

/// Works backwards from a savings goal to the monthly contribution required.
struct GoalView: View {
    @Environment(CalculatorModel.self) private var calculator
    @Environment(AppRouter.self) private var router
    @Environment(\.currencyCode) private var currency

    @AppStorage("goal.target") private var target = 100_000.0
    @AppStorage("goal.initial") private var initialInvestment = 5_000.0
    @AppStorage("goal.years") private var years = 20
    @AppStorage("goal.return") private var annualReturn = 7.0
    @AppStorage("goal.ter") private var expenseRatio = 0.2
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 44

    private var plan: SavingsPlan {
        var plan = SavingsPlan()
        plan.initialInvestment = initialInvestment
        plan.years = years
        plan.annualReturn = annualReturn
        plan.expenseRatio = expenseRatio
        plan.contributionIncrease = 0
        plan.inflation = calculator.plan.inflation
        plan.monthlyContribution = plan.requiredMonthlyContribution(toReach: target) ?? 0
        return plan
    }

    var body: some View {
        let plan = plan
        let projection = Projection(plan: plan)

        NavigationStack {
            Form {
                Section {
                    HeroCard(theme: .goal) {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Monthly Savings Needed")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .textCase(.uppercase)
                                Text(plan.monthlyContribution, format: .currency(code: currency))
                                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: plan.monthlyContribution))
                                    .animation(.snappy, value: plan.monthlyContribution)
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                                CardBadge {
                                    if plan.monthlyContribution == 0 {
                                        Label("Your initial investment alone reaches this goal.", systemImage: "checkmark.seal.fill")
                                    } else {
                                        Label {
                                            Text("Goal \(Text(target, format: .wholeCurrency(currency))) · ^[\(years) Year](inflect: true)")
                                        } icon: {
                                            Image(systemName: "flag.checkered")
                                        }
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)

                            VStack(alignment: .leading, spacing: 10) {
                                GrowthChart(projection: projection, target: target, selectedYear: .constant(nil))
                                ChartLegend()
                            }

                            if plan.monthlyContribution > 0 {
                                HStack(spacing: 0) {
                                    GoalFigure(title: "Per Day", value: plan.monthlyContribution * 12 / 365)
                                    Divider().overlay(.white.opacity(0.3))
                                    GoalFigure(title: "Per Year", value: plan.monthlyContribution * 12)
                                    Divider().overlay(.white.opacity(0.3))
                                    GoalFigure(title: "Returns", value: projection.totalGains)
                                }
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }
                    .heroRow()
                }

                Section("Your Goal") {
                    CurrencyInputRow(title: "Target Amount", value: $target, systemImage: "flag.checkered", color: .indigo)
                    CurrencyInputRow(title: "Initial Investment", value: $initialInvestment, systemImage: "banknote.fill", color: .green)
                    YearsInputRow(years: $years)
                    VStack(alignment: .leading, spacing: 10) {
                        NumberInputRow(title: "Expected Return", value: $annualReturn, unit: "% p.a.", systemImage: "chart.line.uptrend.xyaxis", color: .teal)
                        ReturnPresets(value: $annualReturn)
                    }
                    NumberInputRow(title: "Fund Costs (TER)", value: $expenseRatio, unit: "% p.a.", systemImage: "percent", color: .red)
                }

                ProjectionSummarySection(projection: projection)

                NativeAdSection(slot: 1)

                Section {
                    Button("Use in Calculator", systemImage: "arrow.uturn.backward") {
                        calculator.plan = plan
                        router.selectedTab = .calculator
                    }
                    .disabled(plan.monthlyContribution == 0)
                }
            }
            .navigationTitle("Savings Goal")
            .themedBackground(.goal)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        router.isShowingSettings = true
                    }
                }
            }
        }
    }
}

/// Small key figure on the goal card.
private struct GoalFigure: View {
    let title: LocalizedStringKey
    let value: Double

    @Environment(\.currencyCode) private var currency

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
            Text(value, format: .wholeCurrency(currency))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
