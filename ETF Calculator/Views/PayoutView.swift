//
//  PayoutView.swift
//  ETF Calculator
//

import Charts
import SwiftUI

/// Premium: how long the capital lasts with regular withdrawals.
struct PayoutView: View {
    @Environment(StoreManager.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.currencyCode) private var currency

    @AppStorage(PayoutPlan.Key.capital) private var capital = PayoutPlan().capital
    @AppStorage(PayoutPlan.Key.withdrawal) private var monthlyWithdrawal = PayoutPlan().monthlyWithdrawal
    @AppStorage(PayoutPlan.Key.annualReturn) private var annualReturn = PayoutPlan().annualReturn
    @AppStorage(PayoutPlan.Key.increase) private var withdrawalIncrease = PayoutPlan().withdrawalIncrease

    private var plan: PayoutPlan {
        PayoutPlan(
            capital: capital,
            monthlyWithdrawal: monthlyWithdrawal,
            annualReturn: annualReturn,
            withdrawalIncrease: withdrawalIncrease
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.hasPremiumFeatures {
                    content
                } else {
                    ProTeaserView(
                        title: "Payout Plan",
                        message: "Find out how long your savings last when you withdraw a monthly amount in retirement — including returns and rising withdrawals.",
                        systemImage: "arrow.down.forward.circle"
                    )
                }
            }
            .navigationTitle("Payout")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        router.isShowingSettings = true
                    }
                }
            }
        }
    }

    private var content: some View {
        let projection = PayoutProjection(plan: plan)

        return Form {
            Section {
                HeroCard(theme: .payout) {
                    VStack(alignment: .leading, spacing: 18) {
                        PayoutHeader(projection: projection)
                        PayoutChart(projection: projection)
                    }
                }
                .heroRow()
            }

            Section("Your Payout") {
                CurrencyInputRow(title: "Capital", value: $capital, systemImage: "building.columns.fill", color: .green)
                CurrencyInputRow(title: "Monthly Withdrawal", value: $monthlyWithdrawal, systemImage: "arrow.down.circle.fill", color: .orange)
                NumberInputRow(title: "Return During Payout", value: $annualReturn, unit: "% p.a.", systemImage: "chart.line.uptrend.xyaxis", color: .teal)
                NumberInputRow(title: "Yearly Increase", value: $withdrawalIncrease, unit: "%", systemImage: "arrow.up.forward", color: .pink)
            }

            Section {
                LabeledContent("Total Withdrawn") {
                    Text(projection.totalWithdrawn, format: .currency(code: currency))
                }
                LabeledContent {
                    Text(projection.perpetualWithdrawal, format: .currency(code: currency))
                } label: {
                    Text("Perpetual Withdrawal")
                    Text("Per month without using up capital")
                }
                Button("Use Perpetual Withdrawal", systemImage: "infinity") {
                    withAnimation(.snappy) {
                        monthlyWithdrawal = projection.perpetualWithdrawal.rounded()
                        withdrawalIncrease = 0
                    }
                }
            } header: {
                Text("Summary")
            } footer: {
                Text("Withdrawals are taken at the start of each month; the remaining capital keeps earning the expected return. Taxes are not considered.")
            }
            .monospacedDigit()
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .themedBackground(.payout)
    }
}

private struct PayoutHeader: View {
    let projection: PayoutProjection

    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Capital Lasts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .textCase(.uppercase)

            Group {
                if let months = projection.monthsUntilDepleted {
                    let years = months / 12
                    let remainder = months % 12
                    if remainder == 0 {
                        Text("^[\(years) Year](inflect: true)")
                    } else {
                        Text("^[\(years) Year](inflect: true), ^[\(remainder) Month](inflect: true)")
                    }
                } else {
                    Text("Indefinitely")
                }
            }
            .font(.system(size: valueSize, weight: .bold, design: .rounded))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.snappy, value: projection.monthsUntilDepleted)

            if projection.monthsUntilDepleted == nil {
                CardBadge {
                    Label("Returns cover your withdrawals", systemImage: "infinity")
                }
            } else if let months = projection.monthsUntilDepleted {
                let end = Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now
                CardBadge {
                    Label("Until \(end.formatted(.dateTime.month(.wide).year()))", systemImage: "calendar")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PayoutChart: View {
    let projection: PayoutProjection

    @ScaledMetric(relativeTo: .caption2) private var chartHeight: CGFloat = 200

    private var visiblePoints: [PayoutProjection.Point] {
        // Long-lasting plans are cut at 50 years to keep the chart readable.
        let limit = projection.monthsUntilDepleted.map { $0 / 12 + 1 } ?? 50
        return projection.points.filter { $0.year <= limit }
    }

    var body: some View {
        Chart(visiblePoints) { point in
            AreaMark(
                x: .value("Year", point.year),
                y: .value("Capital", point.balance)
            )
            .foregroundStyle(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Year", point.year),
                y: .value("Capital", point.balance)
            )
            .foregroundStyle(.white)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .interpolationMethod(.monotone)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.white.opacity(0.2))
                AxisValueLabel {
                    if let year = value.as(Int.self) {
                        Text("Y\(year)")
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.white.opacity(0.2))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .number.notation(.compactName))
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.caption2)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: min(chartHeight, 230))
        .accessibilityLabel("Capital over time")
    }
}
