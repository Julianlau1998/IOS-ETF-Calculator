//
//  PortfolioView.swift
//  ETF Calculator
//

import Charts
import SwiftData
import SwiftUI

/// Compares the latest recorded portfolio value with the plan.
struct PortfolioComparison {
    let actual: Double
    let planned: Double
    let date: Date

    var difference: Double { actual - planned }
    var relativeDifference: Double { planned > 0 ? difference / planned : 0 }
    var isAhead: Bool { difference >= 0 }

    init?(entries: [PortfolioEntry], plan: SavingsPlan, startDate: Date?) {
        guard let startDate, let latest = entries.max(by: { $0.date < $1.date }) else { return nil }
        actual = latest.value
        planned = plan.plannedValue(at: latest.date, startDate: startDate)
        date = latest.date
    }
}

/// Row in the calculator linking to "My Portfolio".
struct PortfolioSection: View {
    @Environment(CalculatorModel.self) private var calculator
    @Environment(AppRouter.self) private var router
    @Environment(\.currencyCode) private var currency
    @Query(sort: \PortfolioEntry.date) private var entries: [PortfolioEntry]

    var body: some View {
        Section {
            Button {
                router.selectedTab = .portfolio
            } label: {
                HStack(spacing: 12) {
                    IconTile(systemImage: "briefcase.fill", color: .brown, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Portfolio")
                            .font(.headline)
                        if let setup = calculator.portfolioComparisonPlan,
                           let comparison = PortfolioComparison(entries: entries, plan: setup.plan, startDate: setup.start) {
                            ComparisonLabel(comparison: comparison)
                                .font(.subheadline)
                        } else {
                            Text("Track your real portfolio")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let latest = entries.last {
                        Text(latest.value, format: .wholeCurrency(currency))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .foregroundStyle(.primary)
        }
    }
}

/// "▲ 4 % ahead of plan" / "▼ 3 % behind plan".
struct ComparisonLabel: View {
    let comparison: PortfolioComparison

    var body: some View {
        let percent = abs(comparison.relativeDifference).formatted(.percent.precision(.fractionLength(0...1)))
        Label {
            Text(comparison.isAhead ? "\(percent) ahead of plan" : "\(percent) behind plan")
        } icon: {
            Image(systemName: comparison.isAhead ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .imageScale(.small)
        }
        .foregroundStyle(comparison.isAhead ? .green : .orange)
        .monospacedDigit()
    }
}

struct PortfolioView: View {
    @Environment(CalculatorModel.self) private var calculator
    @Environment(StoreManager.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currencyCode) private var currency
    @Query(sort: \PortfolioEntry.date, order: .reverse) private var entries: [PortfolioEntry]
    @Query private var holdings: [Holding]

    @AppStorage(ReminderService.storageKey) private var isReminderOn = false
    @State private var isAddingEntry = false
    @State private var prefilledValue: Double?
    @State private var celebratedMilestone: CelebratedMilestone?
    @State private var isEditingPlan = false

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("My Portfolio")
            .themedBackground(.growth)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        router.isShowingSettings = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Value", systemImage: "plus") {
                        prefilledValue = nil
                        isAddingEntry = true
                    }
                }
            }
            .sheet(isPresented: $isAddingEntry) {
                AddPortfolioEntryView(initialValue: prefilledValue ?? 0) { value, date in
                    record(value, on: date)
                }
                .presentationDetents([.medium])
            }
            .sheet(item: Binding(
                get: { store.hasPremiumFeatures ? router.pendingImport : nil },
                set: { router.pendingImport = $0 }
            )) { pending in
                ImportPreview(result: pending.result) { total in
                    record(total, on: .now)
                }
            }
            .onChange(of: router.pendingImport?.id) {
                // Importing positions is a Premium feature.
                if router.pendingImport != nil, !store.hasPremiumFeatures {
                    router.pendingImport = nil
                    router.isShowingPaywall = true
                }
            }
            .alert("Import Failed", isPresented: Binding(
                get: { router.importError != nil },
                set: { if !$0 { router.importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(router.importError ?? "")
            }
            .sheet(item: $celebratedMilestone) { milestone in
                MilestoneCelebrationView(amount: milestone.amount)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isEditingPlan) {
                PortfolioPlanEditor()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Track Your Portfolio", systemImage: "briefcase.fill")
        } description: {
            Text("Import your positions from your broker or record your portfolio value from time to time to follow how it develops.")
        } actions: {
            Button("Add First Value", systemImage: "plus") {
                prefilledValue = nil
                isAddingEntry = true
            }
            .buttonStyle(.glassProminent)
        }
    }

    @ViewBuilder
    private var content: some View {
        let setup = calculator.portfolioComparisonPlan
        let comparison = setup.flatMap { PortfolioComparison(entries: entries, plan: $0.plan, startDate: $0.start) }
        let latest = entries.first

        Form {
            if let latest {
                Section {
                    PortfolioHero(latest: latest, comparison: comparison, entries: entries, setup: setup)
                        .heroRow()
                }

                PerformanceSection(latest: latest, comparison: comparison, setup: setup, entries: entries)

                PlanComparisonSection(comparison: comparison) {
                    isEditingPlan = true
                }

                if let comparison, let setup {
                    ForecastSection(comparison: comparison, plan: setup.plan, startDate: setup.start)
                }
            }

            NativeAdSection(slot: 3)

            HoldingsSection { total in
                // Prices were refreshed or positions imported: keep today's value current.
                record(total, on: .now)
            }
            .id("allocation")

            CostCheckSection(plan: setup?.plan ?? calculator.plan, startDate: setup?.start ?? .now)

            RebalancingSection(monthlyContribution: setup?.plan.monthlyContribution ?? calculator.plan.monthlyContribution)

            DividendsSection()

            Section {
                Toggle(isOn: $isReminderOn) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "bell.badge.fill", color: .red)
                        Text("Monthly Reminder")
                    }
                }
                .onChange(of: isReminderOn) { _, isOn in
                    if isOn {
                        Task {
                            if !(await ReminderService.enable()) { isReminderOn = false }
                        }
                    } else {
                        ReminderService.disable()
                    }
                }
            } footer: {
                Text("The reminder to record your portfolio value arrives on the 1st of every month.")
            }

            Section {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.date, format: .dateTime.day().month().year())
                        Spacer()
                        Text(entry.value, format: .currency(code: currency))
                            .monospacedDigit()
                    }
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(entries[index]) }
                }
                Button("Add Value", systemImage: "plus.circle.fill") {
                    prefilledValue = nil
                    isAddingEntry = true
                }
            } header: {
                Text("Recorded Values")
            }
        }
        .refreshable {
            // Pull to refresh: fetch current prices and record today's value.
            if let total = try? await PortfolioPricing.refresh(holdings: holdings, force: true) {
                record(total, on: .now)
            }
        }
        .screenshotScrollTarget()
    }

    /// Saves a portfolio value (one entry per day) and celebrates crossed milestones.
    private func record(_ value: Double, on date: Date) {
        guard value > 0 else { return }
        let previousMax = entries.map(\.value).max() ?? 0
        if let sameDay = entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            sameDay.value = value
        } else {
            modelContext.insert(PortfolioEntry(date: date, value: value))
        }
        if let crossed = Milestone.roundAmounts.last(where: { previousMax < $0 && value >= $0 }), previousMax > 0 {
            celebratedMilestone = CelebratedMilestone(amount: crossed)
        }
    }
}

/// Drives the celebration sheet.
private struct CelebratedMilestone: Identifiable {
    let amount: Double
    var id: Double { amount }
}

private struct PortfolioHero: View {
    let latest: PortfolioEntry
    let comparison: PortfolioComparison?
    let entries: [PortfolioEntry]
    let setup: (plan: SavingsPlan, start: Date)?

    @Environment(\.currencyCode) private var currency
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 44
    @Query private var holdings: [Holding]

    var body: some View {
        HeroCard(theme: .growth) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actual Value")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .textCase(.uppercase)
                    Text(latest.value, format: .currency(code: currency))
                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    if let comparison {
                        CardBadge {
                            HStack(spacing: 6) {
                                Image(systemName: comparison.isAhead ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                Text(comparison.difference, format: .currency(code: currency).sign(strategy: .always()))
                                Text("vs. plan")
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .monospacedDigit()
                        }
                    } else if case let cost = holdings.reduce(0, { $0 + $1.costBasis }), cost > 0 {
                        // Without a plan: gain compared to what was really paid in.
                        CardBadge {
                            HStack(spacing: 6) {
                                Image(systemName: latest.value >= cost ? "arrow.up.right" : "arrow.down.right")
                                Text(latest.value - cost, format: .currency(code: currency).sign(strategy: .always()))
                                Text("(\(((latest.value - cost) / cost).formatted(.percent.precision(.fractionLength(0...1)))))")
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .monospacedDigit()
                        }
                    }
                }
                PortfolioChart(entries: entries, plan: setup?.plan, startDate: setup?.start)
                Text("As of \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// Money paid in, gain so far and the planned value for comparison.
private struct PerformanceSection: View {
    let latest: PortfolioEntry
    let comparison: PortfolioComparison?
    let setup: (plan: SavingsPlan, start: Date)?
    let entries: [PortfolioEntry]

    @Environment(\.currencyCode) private var currency
    @Query private var holdings: [Holding]

    var body: some View {
        let costBasis = holdings.reduce(0) { $0 + $1.costBasis }
        let planned = setup.map { $0.plan.plannedState(afterMonths: SavingsPlan.monthsElapsed(from: $0.start, to: latest.date)) }
        // What was really paid in; falls back to the plan only if one is set up.
        let invested = costBasis > 0 ? costBasis : (planned?.contributions ?? 0)
        let gain = latest.value - invested
        let gainShare = invested > 0 ? gain / invested : 0

        Section {
            if invested > 0 {
                LabeledContent {
                    Text(invested, format: .currency(code: currency))
                } label: {
                    Text("Paid In So Far")
                    if costBasis == 0 {
                        Text("Estimated from your savings plan")
                    }
                }
                LabeledContent("Gain So Far") {
                    HStack(spacing: 6) {
                        Text(gain, format: .currency(code: currency).sign(strategy: .always()))
                        Text("(\(gainShare.formatted(.percent.precision(.fractionLength(0...1)).sign(strategy: .always()))))")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(gain >= 0 ? .green : .red)
                }
            }
            if let comparison, let planned, let setup {
                let months = SavingsPlan.monthsElapsed(from: setup.start, to: latest.date)
                if costBasis > 0 {
                    LabeledContent("Planned Contributions") {
                        Text(planned.contributions, format: .currency(code: currency))
                    }
                }
                LabeledContent("Planned Value") {
                    Text(comparison.planned, format: .currency(code: currency))
                }
                LabeledContent("Savings Plan Running For") {
                    Text("^[\(months / 12) Year](inflect: true), ^[\(months % 12) Month](inflect: true)")
                }
            }
            let streak = PortfolioStreak.months(in: entries.map(\.date))
            if streak > 1 {
                LabeledContent {
                    Text("^[\(streak) Month](inflect: true)")
                } label: {
                    Label {
                        Text("Tracking Streak")
                    } icon: {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, options: .nonRepeating)
                    }
                }
            }
        } header: {
            Text("Performance")
        } footer: {
            if costBasis == 0 {
                Text("Import your positions from your broker to see what you really paid in.")
            }
        }
        .monospacedDigit()
    }
}

/// Optional comparison with the user's real savings plan.
private struct PlanComparisonSection: View {
    let comparison: PortfolioComparison?
    let onEdit: () -> Void

    @Environment(CalculatorModel.self) private var calculator
    @Environment(\.currencyCode) private var currency

    var body: some View {
        Section {
            if let setup = calculator.portfolioComparisonPlan {
                Button(action: onEdit) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "calendar.badge.checkmark", color: .blue, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(setup.plan.monthlyContribution.formatted(.currency(code: currency).precision(.fractionLength(0))))/mo since \(setup.start.formatted(.dateTime.month(.wide).year()))")
                                .foregroundStyle(.primary)
                            if let comparison {
                                ComparisonLabel(comparison: comparison)
                                    .font(.subheadline)
                            }
                        }
                        Spacer()
                        Text("Edit")
                            .foregroundStyle(.tint)
                    }
                }
            } else {
                Button(action: onEdit) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "calendar.badge.plus", color: .blue, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Compare with Your Savings Plan")
                                .foregroundStyle(.primary)
                            Text("Enter when you started and how much you save — see whether you're ahead or behind.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Savings Plan")
        }
    }
}

/// Sets up the real savings plan used for the comparison.
private struct PortfolioPlanEditor: View {
    @Environment(CalculatorModel.self) private var calculator
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date.now
    @State private var plan = SavingsPlan()
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(selection: $startDate, in: ...Date.now, displayedComponents: .date) {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "calendar", color: .blue)
                            Text("Started On")
                        }
                    }
                    CurrencyInputRow(title: "Initial Investment", value: $plan.initialInvestment, systemImage: "banknote.fill", color: .green)
                    CurrencyInputRow(title: "Monthly Contribution", value: $plan.monthlyContribution, systemImage: "calendar.badge.plus", color: .blue)
                    NumberInputRow(title: "Expected Return", value: $plan.annualReturn, unit: "% p.a.", systemImage: "chart.line.uptrend.xyaxis", color: .teal)
                    YearsInputRow(years: $plan.years)
                } footer: {
                    Text("Your real savings plan — independent of the calculator, so you can keep playing with numbers there. If you imported from your broker, start date and monthly amount are suggested from your purchases.")
                }

                Section {
                    Button("Use Values from Calculator", systemImage: "arrow.down.doc") {
                        withAnimation { plan = calculator.plan }
                    }
                    if calculator.portfolioPlan != nil {
                        Button("Remove Comparison", systemImage: "trash", role: .destructive) {
                            calculator.portfolioPlan = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Savings Plan")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        UIApplication.shared.dismissKeyboard()
                        Task { @MainActor in
                            // Number fields commit on end of editing.
                            try? await Task.sleep(for: .milliseconds(80))
                            calculator.planStartDate = startDate
                            calculator.portfolioPlan = plan
                            dismiss()
                        }
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let existing = calculator.portfolioPlan {
            plan = existing
            startDate = calculator.planStartDate ?? .now
        } else {
            // Suggest from the broker import, otherwise start from a plain plan.
            var suggestion = SavingsPlan()
            suggestion.initialInvestment = 0
            suggestion.monthlyContribution = calculator.suggestedMonthlyContribution ?? calculator.plan.monthlyContribution
            suggestion.annualReturn = calculator.plan.annualReturn
            suggestion.years = calculator.plan.years
            plan = suggestion
            startDate = calculator.planStartDate ?? .now
        }
    }
}

/// Premium: where the actual portfolio ends up if the plan continues.
private struct ForecastSection: View {
    let comparison: PortfolioComparison
    let plan: SavingsPlan
    let startDate: Date

    @Environment(StoreManager.self) private var store
    @Environment(\.currencyCode) private var currency

    var body: some View {
        Section {
            if store.hasPremiumFeatures {
                let forecast = plan.forecast(fromActual: comparison.actual, at: comparison.date, startDate: startDate)
                let original = Projection(plan: plan).finalValue
                LabeledContent {
                    Text(forecast.finalValue, format: .currency(code: currency))
                        .fontWeight(.semibold)
                } label: {
                    Label("Expected Final Value", systemImage: "sparkles")
                }
                LabeledContent("Compared to Plan") {
                    Text(forecast.finalValue - original, format: .currency(code: currency).sign(strategy: .always()))
                        .foregroundStyle(forecast.finalValue >= original ? .green : .orange)
                }
            } else {
                ProLockedRow(title: "Forecast", subtitle: "Where your real portfolio ends up", systemImage: "sparkles")
            }
        } header: {
            Text("Forecast")
        } footer: {
            if store.hasPremiumFeatures {
                Text("Continues your plan from today's actual value with the same contributions and expected return.")
            }
        }
        .monospacedDigit()
    }
}

/// Planned growth line with the recorded values as points.
private struct PortfolioChart: View {
    let entries: [PortfolioEntry]
    let plan: SavingsPlan?
    let startDate: Date?

    private var plannedPoints: [(date: Date, value: Double)] {
        guard let plan, let startDate else { return [] }
        let latest = entries.map(\.date).max() ?? .now
        let months = max(1, (Calendar.current.dateComponents([.month], from: startDate, to: latest).month ?? 0) + 3)
        return stride(from: 0, through: months, by: max(1, months / 40)).compactMap { month in
            guard let date = Calendar.current.date(byAdding: .month, value: month, to: startDate) else { return nil }
            return (date, plan.plannedValue(afterMonths: month))
        }
    }

    var body: some View {
        Chart {
            ForEach(plannedPoints, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value), series: .value("Series", "Plan"))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            ForEach(entries) { entry in
                LineMark(x: .value("Date", entry.date), y: .value("Value", entry.value), series: .value("Series", "Actual"))
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("Date", entry.date), y: .value("Value", entry.value))
                    .foregroundStyle(.white)
                    .symbolSize(60)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.2))
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.2))
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
        .frame(height: 180)
        .accessibilityLabel("Plan vs. actual")
    }
}

private struct AddPortfolioEntryView: View {
    var initialValue: Double = 0
    let onSave: (Double, Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var value = 0.0

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                CurrencyInputRow(title: "Portfolio Value", value: $value, systemImage: "briefcase.fill", color: .brown)
            }
            .navigationTitle("Add Value")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if value == 0 { value = initialValue } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        // Number fields commit on end of editing, so finish editing first.
                        UIApplication.shared.dismissKeyboard()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(80))
                            onSave(value, date)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
