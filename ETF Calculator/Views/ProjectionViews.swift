//
//  ProjectionViews.swift
//  ETF Calculator
//

import Charts
import CoreTransferable
import SwiftUI
import TipKit
import UniformTypeIdentifiers

/// Large, Stocks-style headline value. Shows the selected year while scrubbing the chart.
/// Designed for the white-on-gradient hero card.
struct ProjectionHeader: View {
    let projection: Projection
    var selectedYear: Int?
    /// Shows values in today's purchasing power instead of nominal euros.
    var showsRealValue = false
    var onToggleRealValue: (() -> Void)?

    @Environment(\.currencyCode) private var currency
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 44

    private var value: YearlyValue? {
        if let selectedYear, let match = projection.values.first(where: { $0.year == selectedYear }) {
            return match
        }
        return projection.values.last
    }

    var body: some View {
        let value = value
        let year = value?.year ?? 0
        let gains = value?.gains ?? 0
        let contributions = value?.contributions ?? 0
        let shown = showsRealValue ? (value?.realBalance ?? 0) : (value?.balance ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if showsRealValue {
                        Text(selectedYear == nil ? "In Today's Money" : "Year \(year) in Today's Money")
                    } else {
                        Text(selectedYear == nil ? "Final Value" : "Value after Year \(year)")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .textCase(.uppercase)
                .contentTransition(.interpolate)

                Spacer(minLength: 8)

                if let onToggleRealValue, projection.plan.inflation > 0 {
                    // Stocks-style toggle between nominal and inflation-adjusted values.
                    Button(action: onToggleRealValue) {
                        Label(showsRealValue ? "Nominal" : "Purchasing Power", systemImage: "arrow.left.arrow.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Switches between nominal values and today's purchasing power")
                }
            }

            Text(shown, format: .currency(code: currency))
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: shown))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)

            if showsRealValue, let value {
                CardBadge {
                    Text("\(value.balance.formatted(.currency(code: currency).precision(.fractionLength(0)))) nominal")
                        .monospacedDigit()
                }
            } else if gains != 0 {
                CardBadge {
                    HStack(spacing: 6) {
                        Image(systemName: gains > 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(gains, format: .currency(code: currency).sign(strategy: .always()))
                        if contributions > 0 {
                            Text("(\((gains / contributions).formatted(.percent.precision(.fractionLength(0...1)))))")
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .monospacedDigit()
                    .contentTransition(.numericText())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: shown)
        .accessibilityElement(children: .contain)
    }
}

/// Stacked area chart of contributions vs. returns with drag-to-inspect,
/// an optional Monte Carlo range and an optional target line.
/// Styled in white tones for the hero card.
struct GrowthChart: View {
    let projection: Projection
    var range: RangeProjection?
    var target: Double?
    @Binding var selectedYear: Int?
    /// Off for static renderings (e.g. share images), where there's no appear animation.
    var animatesIn = true

    /// Grows the chart from the baseline when it first appears.
    @State private var appearance: Double = 0
    /// Taller plot area for larger text sizes so axis labels keep their room.
    @ScaledMetric(relativeTo: .caption2) private var chartHeight: CGFloat = 200

    private let investedLabel = String(localized: "Invested")
    private let returnsLabel = String(localized: "Returns")
    private let rangeLabel = String(localized: "Range")

    var body: some View {
        let progress = animatesIn ? appearance : 1
        Chart {
            if let range {
                ForEach(range.bands) { band in
                    AreaMark(
                        x: .value("Year", band.year),
                        yStart: .value("Low", band.low * progress),
                        yEnd: .value("High", band.high * progress),
                        series: .value("Series", rangeLabel)
                    )
                    .foregroundStyle(.white.opacity(0.12))
                    .interpolationMethod(.monotone)
                }
                // Dashed edges make the range readable and match the legend.
                ForEach(range.bands) { band in
                    LineMark(x: .value("Year", band.year), y: .value("High", band.high * progress), series: .value("Series", "RangeHigh"))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Year", band.year), y: .value("Low", band.low * progress), series: .value("Series", "RangeLow"))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .interpolationMethod(.monotone)
                }
            }

            ForEach(projection.values) { value in
                AreaMark(
                    x: .value("Year", value.year),
                    y: .value("Amount", value.contributions * progress),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("Series", investedLabel))
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Year", value.year),
                    y: .value("Amount", max(0, value.gains) * progress),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("Series", returnsLabel))
                .interpolationMethod(.monotone)
            }

            ForEach(projection.values) { value in
                LineMark(
                    x: .value("Year", value.year),
                    y: .value("Amount", value.balance * progress),
                    series: .value("Series", "Total")
                )
                .foregroundStyle(.white)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }

            if let target {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        Label("Goal", systemImage: "flag.checkered")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
            }

            if let selectedYear, let value = projection.values.first(where: { $0.year == selectedYear }) {
                RuleMark(x: .value("Year", selectedYear))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Year", selectedYear),
                    y: .value("Amount", value.balance)
                )
                .symbolSize(110)
                .foregroundStyle(.white)
                .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    Text("Year \(selectedYear) · \(String(Calendar.current.component(.year, from: .now) + selectedYear))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                }
            }
        }
        .chartForegroundStyleScale([
            investedLabel: LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
            returnsLabel: LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.28)], startPoint: .top, endPoint: .bottom)
        ])
        .chartXSelection(value: $selectedYear)
        .chartXScale(domain: 0...max(1, projection.plan.years))
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
        .chartLegend(.hidden)
        .font(.caption2)
        // Axis labels stop growing at accessibility sizes so they're never clipped;
        // the exact values remain available in the header and summary.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: min(chartHeight, 240))
        .sensoryFeedback(.selection, trigger: selectedYear)
        .onAppear {
            withAnimation(.smooth(duration: 0.9)) { appearance = 1 }
        }
        .accessibilityLabel("Growth chart")
        .accessibilityChartDescriptor(self)
    }
}

/// Lets VoiceOver users explore the chart, including Audio Graphs.
extension GrowthChart: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let values = projection.values
        let maxValue = values.map(\.balance).max() ?? 1
        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Year"),
            range: 0...Double(max(1, projection.plan.years)),
            gridlinePositions: []
        ) { String(localized: "Year \(Int($0))") }
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Value"),
            range: 0...max(1, maxValue),
            gridlinePositions: []
        ) { $0.formatted(.number.notation(.compactName)) }
        let balance = AXDataSeriesDescriptor(
            name: String(localized: "Total"),
            isContinuous: true,
            dataPoints: values.map { AXDataPoint(x: Double($0.year), y: $0.balance) }
        )
        let invested = AXDataSeriesDescriptor(
            name: String(localized: "Invested"),
            isContinuous: true,
            dataPoints: values.map { AXDataPoint(x: Double($0.year), y: $0.contributions) }
        )
        return AXChartDescriptor(
            title: String(localized: "Growth chart"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [balance, invested]
        )
    }
}

/// Donut showing how much of the final value comes from returns.
struct ReturnShareRing: View {
    let projection: Projection

    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 70

    var body: some View {
        let share = projection.gainShare
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 9)
            Circle()
                .trim(from: 0, to: share)
                .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: share)
            VStack(spacing: 0) {
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: share))
                Text("Returns")
                    .font(.caption2.weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white.opacity(0.75))
                    .textCase(.uppercase)
            }
        }
        .frame(width: min(size, 120), height: min(size, 120))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Share of Returns")
    }
}

/// Legend row on the hero card, e.g. "● Invested 13,000 €".
private struct CardLegendRow: View {
    let title: LocalizedStringKey
    let value: Double
    let opacity: Double

    @Environment(\.currencyCode) private var currency

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(opacity))
                .frame(width: 12, height: 12)
            Text(title)
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 8)
            Text(value, format: .wholeCurrency(currency))
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                // Large amounts shrink a little instead of being cut off.
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
        }
        .font(.subheadline)
        .lineLimit(1)
    }
}

/// Explains every layer of the growth chart.
struct ChartLegend: View {
    var showsRange = false

    var body: some View {
        // Falls back to two rows when the items don't fit next to each other.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    total
                    invested
                    returns
                }
                if showsRange { range }
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var items: some View {
        total
        invested
        returns
        if showsRange { range }
    }

    private var total: some View {
        legendItem("Total") {
            Capsule().fill(.white).frame(width: 14, height: 3)
        }
    }

    private var invested: some View {
        legendItem("Invested") {
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.3)).frame(width: 12, height: 12)
        }
    }

    private var returns: some View {
        legendItem("Returns") {
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.6)).frame(width: 12, height: 12)
        }
    }

    private var range: some View {
        legendItem("Range (80% of simulations)") {
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                .frame(width: 12, height: 12)
        }
    }

    private func legendItem(_ title: LocalizedStringKey, @ViewBuilder symbol: () -> some View) -> some View {
        HStack(spacing: 5) {
            symbol()
            Text(title).lineLimit(1)
        }
    }
}

/// Hero card combining headline value, chart and return breakdown.
struct ProjectionOverview: View {
    let projection: Projection
    var range: RangeProjection?
    var theme: CardTheme = .growth
    @State private var selectedYear: Int?
    @AppStorage("overview.showsRealValue") private var showsRealValue = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let chartTip = ChartScrubTip()

    var body: some View {
        HeroCard(theme: theme) {
            VStack(alignment: .leading, spacing: 18) {
                ProjectionHeader(
                    projection: projection,
                    selectedYear: selectedYear,
                    showsRealValue: showsRealValue && projection.plan.inflation > 0
                ) {
                    withAnimation(.snappy) { showsRealValue.toggle() }
                }
                VStack(alignment: .leading, spacing: 10) {
                    GrowthChart(projection: projection, range: range, selectedYear: $selectedYear)
                        .popoverTip(chartTip, arrowEdge: .bottom)
                        .onChange(of: selectedYear) { _, year in
                            if year != nil { chartTip.invalidate(reason: .actionPerformed) }
                        }
                    ChartLegend(showsRange: range != nil)
                }
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                    : AnyLayout(HStackLayout(spacing: 16))
                layout {
                    ReturnShareRing(projection: projection)
                    VStack(spacing: 10) {
                        CardLegendRow(title: "Invested", value: projection.totalContributions, opacity: 0.35)
                        CardLegendRow(title: "Returns", value: projection.totalGains, opacity: 0.7)
                    }
                }
                .padding(14)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
                .animation(.snappy, value: projection.finalValue)
            }
        }
    }
}

/// Key figures of a projection as grouped list rows.
struct ProjectionSummarySection: View {
    let projection: Projection

    @Environment(\.currencyCode) private var currency
    @Environment(\.taxSettings) private var taxSettings
    @Environment(StoreManager.self) private var store

    var body: some View {
        Section {
            LabeledContent("Total Invested") {
                Text(projection.totalContributions, format: .currency(code: currency))
            }
            LabeledContent("Investment Returns") {
                Text(projection.totalGains, format: .currency(code: currency).sign(strategy: .always()))
                    .foregroundStyle(projection.totalGains >= 0 ? .green : .red)
            }
            if projection.totalCosts > 0 {
                LabeledContent("Fund Costs") {
                    Text(-projection.totalCosts, format: .currency(code: currency))
                }
            }
            if projection.plan.inflation > 0 {
                LabeledContent("In Today's Money") {
                    Text(projection.realFinalValue, format: .currency(code: currency))
                }
            }
            if taxSettings.isEnabled {
                if store.hasPremiumFeatures {
                    let breakdown = projection.taxBreakdown(taxSettings)
                    let taxes = breakdown.total
                    LabeledContent(taxSettings.region == .germany ? "Capital Gains Tax" : "Taxes") {
                        Text(-taxes, format: .currency(code: currency))
                    }
                    if taxSettings.region == .germany && taxSettings.includesAdvanceLumpSum {
                        LabeledContent {
                            Text(-breakdown.yearlyTaxes, format: .currency(code: currency))
                        } label: {
                            Text("Thereof Yearly (Vorabpauschale)")
                                .padding(.leading, 12)
                        }
                        .foregroundStyle(.secondary)
                        LabeledContent {
                            Text(-breakdown.finalTax, format: .currency(code: currency))
                        } label: {
                            Text("Thereof on Sale")
                                .padding(.leading, 12)
                        }
                        .foregroundStyle(.secondary)
                    }
                    LabeledContent {
                        Text(projection.finalValue - taxes, format: .currency(code: currency))
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    } label: {
                        Text("After Taxes")
                            .fontWeight(.semibold)
                    }
                } else {
                    ProLockedRow(title: "After Taxes", subtitle: "Capital gains tax and allowances", systemImage: "building.columns")
                }
            }
        } header: {
            Text("Summary")
        } footer: {
            if projection.plan.inflation > 0 {
                Text("“In Today's Money” shows the final value adjusted for \(projection.plan.inflation.percentText()) annual inflation.")
            }
        }
        .monospacedDigit()
    }
}

/// Pessimistic / expected / optimistic outcomes from the Monte Carlo simulation.
struct RangeSection: View {
    let range: RangeProjection?

    @Environment(\.currencyCode) private var currency
    @Environment(\.volatility) private var volatility

    var body: some View {
        Section {
            if let final = range?.final, let range {
                rangeRow("Pessimistic", systemImage: "cloud.rain", color: .orange, value: final.low)
                rangeRow("Typical", systemImage: "sun.haze", color: .yellow, value: final.median)
                rangeRow("Optimistic", systemImage: "sun.max", color: .green, value: final.high)
                LabeledContent("Chance of Profit") {
                    Text(range.probabilityOfGain, format: .percent.precision(.fractionLength(0)))
                }
            } else {
                ProLockedRow(title: "Range of Outcomes", subtitle: "500 simulated market paths", systemImage: "chart.line.text.clipboard")
            }
        } header: {
            Text("Market Fluctuations")
        } footer: {
            if range != nil {
                Text("Based on \(RangeProjection.simulationCount) simulations with \(volatility.percentText(0...1)) annual volatility. 8 of 10 outcomes fall between pessimistic and optimistic.")
            }
        }
        .monospacedDigit()
    }

    private func rangeRow(_ title: LocalizedStringKey, systemImage: String, color: Color, value: Double) -> some View {
        LabeledContent {
            Text(value, format: .currency(code: currency))
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(color)
            }
        }
    }
}

/// When round amounts are reached, shown as Fitness-style award badges.
struct MilestonesSection: View {
    let projection: Projection

    var body: some View {
        let milestones = projection.milestones
        if !milestones.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                            MilestoneBadge(milestone: milestone, index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .heroRow()
            } header: {
                Text("Milestones")
            }
        }
    }
}

private struct MilestoneBadge: View {
    let milestone: Milestone
    let index: Int

    @Environment(\.currencyCode) private var currency
    @ScaledMetric(relativeTo: .headline) private var badgeWidth: CGFloat = 104

    private static let palettes: [[Color]] = [
        [.mint, .green], [.teal, .blue], [.blue, .indigo], [.indigo, .purple],
        [.purple, .pink], [.pink, .red], [.orange, .red], [.yellow, .orange]
    ]

    private var symbol: String {
        switch milestone.amount {
        case 1_000_000...: "crown.fill"
        case 250_000...: "trophy.fill"
        case 100_000...: "star.fill"
        default: "flag.checkered"
        }
    }

    var body: some View {
        let colors = Self.palettes[index % Self.palettes.count]
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                    .padding(4)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .frame(width: 64, height: 64)
            .shadow(color: colors[1].opacity(0.35), radius: 8, y: 4)

            Text(milestone.amount, format: .currency(code: currency).notation(.compactName))
                .font(.system(.headline, design: .rounded, weight: .bold))

            VStack(spacing: 0) {
                Text("Year \(milestone.year)")
                    .font(.caption.weight(.semibold))
                Text(verbatim: String(Calendar.current.component(.year, from: .now) + milestone.year))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .frame(width: badgeWidth)
        .padding(.vertical, 14)
        .background(.background, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// CSV file of the yearly table, shared via the share sheet.
struct ProjectionCSV: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName(String(localized: "ETF Savings Plan.csv"))
    }
}

/// A table of the portfolio value at the end of every year.
struct YearlyBreakdownView: View {
    let projection: Projection

    @Environment(\.currencyCode) private var currency
    @Environment(\.taxSettings) private var taxSettings
    @Environment(StoreManager.self) private var store
    @Environment(AppRouter.self) private var router

    private var taxBreakdown: TaxBreakdown? {
        guard store.hasPremiumFeatures, taxSettings.isEnabled, taxSettings.region == .germany, taxSettings.includesAdvanceLumpSum else { return nil }
        return projection.taxBreakdown(taxSettings)
    }

    @Environment(AdsManager.self) private var ads

    var body: some View {
        let taxBreakdown = taxBreakdown
        List {
            ForEach(projection.values.dropFirst()) { value in
                row(for: value, taxBreakdown: taxBreakdown)
                if value.year == min(5, projection.plan.years) {
                    NativeAdRow(slot: 4)
                }
            }
        }
        .navigationTitle("Year by Year")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            ads.registerCompletedAction(isPremium: store.isPremium)
        }
        .toolbar { exportToolbar }
    }

    private func row(for value: YearlyValue, taxBreakdown: TaxBreakdown?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Year \(value.year)")
                    .font(.headline)
                Spacer()
                Text(value.balance, format: .currency(code: currency))
                    .font(.headline)
            }
            HStack {
                Text("Invested \(Text(value.contributions, format: .wholeCurrency(currency)))")
                Spacer()
                Text(value.gains, format: .wholeCurrency(currency).sign(strategy: .always()))
                    .foregroundStyle(value.gains >= 0 ? .green : .red)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let taxYear = taxBreakdown?.year(value.year), taxYear.advanceLumpSum > 0 {
                HStack {
                    Label {
                        Text("Vorabpauschale \(Text(taxYear.advanceLumpSum, format: .wholeCurrency(currency)))")
                    } icon: {
                        Image(systemName: "building.columns")
                    }
                    Spacer()
                    Text("Tax \(Text(taxYear.tax, format: .currency(code: currency)))")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .monospacedDigit()
        .padding(.vertical, 2)
    }

    @ToolbarContentBuilder
    private var exportToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if store.hasPremiumFeatures {
                ShareLink(
                    item: ProjectionCSV(text: projection.csv(currency: currency)),
                    preview: SharePreview(String(localized: "ETF Savings Plan.csv"), image: Image(systemName: "tablecells"))
                ) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            } else {
                Button("Export CSV", systemImage: "lock") {
                    router.isShowingPaywall = true
                }
            }
        }
    }
}

/// Short, human-readable description of a plan, e.g. "€100/mo · 10 yrs · 7 %".
struct PlanDescription: View {
    let plan: SavingsPlan

    @Environment(\.currencyCode) private var currency

    var body: some View {
        Text("\(Text(plan.monthlyContribution, format: .wholeCurrency(currency)))/mo · \(plan.years) yrs · \(plan.annualReturn.percentText())")
    }
}

/// Plain-text summary used for sharing a plan.
func shareText(for projection: Projection, currency: String) -> String {
    let plan = projection.plan
    let money = FloatingPointFormatStyle<Double>.Currency(code: currency)
    return String(localized: """
    My ETF savings plan
    Initial investment: \(plan.initialInvestment.formatted(money))
    Monthly: \(plan.monthlyContribution.formatted(money))
    Duration: \(plan.years) years at \(plan.annualReturn.percentText())

    Final value: \(projection.finalValue.formatted(money))
    Invested: \(projection.totalContributions.formatted(money))
    Returns: \(projection.totalGains.formatted(money))
    """)
}
