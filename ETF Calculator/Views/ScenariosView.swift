//
//  ScenariosView.swift
//  ETF Calculator
//

import Charts
import SwiftData
import SwiftUI

/// Saved plans with a comparison chart.
struct ScenariosView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreManager.self) private var store
    @Environment(CalculatorModel.self) private var calculator
    @Query(sort: \Scenario.createdAt, order: .reverse) private var scenarios: [Scenario]

    var body: some View {
        NavigationStack {
            List {
                if scenarios.count > 1 {
                    Section {
                        ComparisonChart(scenarios: scenarios)
                            .padding(.vertical, 8)
                    } header: {
                        Text("Comparison")
                    }
                }

                Section {
                    ForEach(scenarios) { scenario in
                        NavigationLink(value: scenario) {
                            ScenarioRow(scenario: scenario)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Open in Calculator", systemImage: "slider.horizontal.3") {
                                open(scenario)
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button("Open in Calculator", systemImage: "slider.horizontal.3") {
                                open(scenario)
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                duplicate(scenario)
                            }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation { modelContext.delete(scenario) }
                            }
                        } preview: {
                            ScenarioPreview(scenario: scenario)
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    if !store.hasPremiumFeatures && !scenarios.isEmpty {
                        Text("\(min(scenarios.count, StoreManager.freeScenarioLimit)) of \(StoreManager.freeScenarioLimit) free scenarios used. Premium saves unlimited scenarios.")
                    }
                }

                if !scenarios.isEmpty {
                    NativeAdSection(slot: 2)
                }
            }
            .navigationTitle("Scenarios")
            .themedBackground(.scenarios)
            .navigationDestination(for: Scenario.self) { scenario in
                ScenarioDetailView(scenario: scenario)
            }
            .overlay {
                if scenarios.isEmpty {
                    ContentUnavailableView {
                        Label("No Scenarios", systemImage: "bookmark")
                    } description: {
                        Text("Save a plan from the calculator to compare different strategies here.")
                    } actions: {
                        Button("Open Calculator") {
                            router.selectedTab = .calculator
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        router.isShowingSettings = true
                    }
                }
                if !scenarios.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }

    private func open(_ scenario: Scenario) {
        calculator.plan = scenario.plan
        router.selectedTab = .calculator
    }

    private func duplicate(_ scenario: Scenario) {
        guard store.hasPremiumFeatures || scenarios.count < StoreManager.freeScenarioLimit else {
            router.isShowingPaywall = true
            return
        }
        withAnimation {
            modelContext.insert(Scenario(name: String(localized: "\(scenario.name) (Copy)"), plan: scenario.plan))
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scenarios[index])
        }
    }
}

private struct ScenarioRow: View {
    let scenario: Scenario

    private static let palette: [Color] = [.purple, .indigo, .blue, .teal, .green, .orange, .pink]

    /// Stable color per scenario name (String.hashValue is randomized per launch).
    static func color(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    @Environment(\.currencyCode) private var currency

    var body: some View {
        let projection = Projection(plan: scenario.plan)
        let color = ScenarioRow.color(for: scenario.name)
        HStack(spacing: 12) {
            IconTile(systemImage: "chart.line.uptrend.xyaxis", color: color, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                // Name and final value share the first line, so the value never gets cut off.
                HStack(alignment: .firstTextBaseline) {
                    Text(scenario.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(projection.finalValue, format: .wholeCurrency(currency))
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
                HStack {
                    PlanDescription(plan: scenario.plan)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Sparkline(values: projection.values.map(\.balance), color: color)
                        .frame(width: 56, height: 22)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact card shown when long-pressing a scenario.
private struct ScenarioPreview: View {
    let scenario: Scenario

    var body: some View {
        ProjectionOverview(projection: Projection(plan: scenario.plan), theme: .scenarios)
            .frame(width: 360)
    }
}

/// Tiny trend line for list rows.
private struct Sparkline: View {
    let values: [Double]
    var color: Color = .green

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("Year", index), y: .value("Value", value))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Year", index), y: .value("Value", value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

/// One line per scenario so different strategies can be compared at a glance.
private struct ComparisonChart: View {
    let scenarios: [Scenario]

    var body: some View {
        Chart {
            ForEach(scenarios) { scenario in
                ForEach(Projection(plan: scenario.plan).values) { value in
                    LineMark(
                        x: .value("Year", value.year),
                        y: .value("Value", value.balance)
                    )
                    .foregroundStyle(by: .value("Scenario", scenario.name))
                    .interpolationMethod(.monotone)
                }
            }
        }
        // Same colors as the row icons below the chart.
        .chartForegroundStyleScale(
            domain: scenarios.map(\.name),
            range: scenarios.map { ScenarioRow.color(for: $0.name) }
        )
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let year = value.as(Int.self) {
                        Text("Y\(year)")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .number.notation(.compactName))
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .font(.caption2)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(minHeight: 220)
    }
}

/// Read-only details of a saved scenario with the option to load it.
struct ScenarioDetailView: View {
    @Bindable var scenario: Scenario

    @Environment(AdsManager.self) private var ads
    @Environment(StoreManager.self) private var store
    @Environment(CalculatorModel.self) private var calculator
    @Environment(AppRouter.self) private var router
    @Environment(\.currencyCode) private var currency

    var body: some View {
        let projection = Projection(plan: scenario.plan)
        let plan = scenario.plan

        Form {
            Section {
                ProjectionOverview(projection: projection, theme: .scenarios)
                    .heroRow()
            }

            Section("Name") {
                TextField("Name", text: $scenario.name)
            }

            Section("Plan") {
                LabeledContent("Initial Investment") { Text(plan.initialInvestment, format: .currency(code: currency)) }
                LabeledContent("Monthly Contribution") { Text(plan.monthlyContribution, format: .currency(code: currency)) }
                LabeledContent("Duration") { Text("^[\(plan.years) Year](inflect: true)") }
                LabeledContent("Expected Return") { Text("\(plan.annualReturn.percentText()) p.a.") }
                if plan.contributionIncrease > 0 {
                    LabeledContent("Yearly Increase") { Text(verbatim: plan.contributionIncrease.percentText()) }
                }
                LabeledContent("Fund Costs (TER)") { Text("\(plan.expenseRatio.percentText()) p.a.") }
                LabeledContent("Inflation") { Text("\(plan.inflation.percentText()) p.a.") }
            }
            .monospacedDigit()

            ProjectionSummarySection(projection: projection)

            Section {
                NavigationLink {
                    YearlyBreakdownView(projection: projection)
                } label: {
                    Label("Year by Year", systemImage: "list.bullet.rectangle")
                }
                Button("Open in Calculator", systemImage: "slider.horizontal.3") {
                    calculator.plan = scenario.plan
                    router.selectedTab = .calculator
                }
            }
        }
        .navigationTitle(scenario.name)
        .navigationBarTitleDisplayMode(.inline)
        .themedBackground(.scenarios)
        .onDisappear {
            ads.registerCompletedAction(isPremium: store.isPremium)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(for: projection, currency: currency)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
