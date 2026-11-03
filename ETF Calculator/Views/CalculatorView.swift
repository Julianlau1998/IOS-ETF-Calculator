//
//  CalculatorView.swift
//  ETF Calculator
//

import SwiftData
import SwiftUI
import TipKit

struct CalculatorView: View {
    @Environment(CalculatorModel.self) private var calculator
    @Environment(AppRouter.self) private var router
    @Environment(AdsManager.self) private var ads
    @Environment(StoreManager.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currencyCode) private var currency
    @Environment(\.volatility) private var volatility
    @Query private var scenarios: [Scenario]
    @AppStorage(PayoutPlan.Key.capital) private var payoutCapital = PayoutPlan().capital

    @State private var isNamingScenario = false
    @State private var scenarioName = ""
    @State private var savedCount = 0
    @State private var shareImage: RenderedImage?
    @State private var isConfirmingReset = false
    /// Assumptions and special payments are folded away until needed.
    @AppStorage("calculator.showsMoreOptions") private var showsMoreOptions = false
    private let shareTip = ShareImageTip()
    @Environment(\.paletteOverride) private var paletteOverride

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let projection = calculator.projection
        let range = store.hasPremiumFeatures ? calculator.range(volatility: volatility) : nil

        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    // iPad / wide windows: results left, inputs right, scrolling independently.
                    HStack(alignment: .top, spacing: 0) {
                        Form {
                            heroSection(projection, range: range)
                            resultSections(projection, range: range)
                        }
                        Form {
                            inputSections
                        }
                        .frame(width: 400)
                    }
                } else {
                    Form {
                        heroSection(projection, range: range)
                        inputSections
                        resultSections(projection, range: range)
                    }
                    .screenshotScrollTarget()
                }
            }
            #if DEBUG
            .navigationDestination(isPresented: .constant(DemoData.screen == "yearly")) {
                YearlyBreakdownView(projection: projection)
            }
            #endif
            .navigationTitle("Owlvest")
            .themedBackground(.growth)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .toolbar { toolbar(for: projection) }
            .alert("Save Scenario", isPresented: $isNamingScenario) {
                TextField("Name", text: $scenarioName)
                Button("Save", action: saveScenario)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save this plan to compare it with other scenarios.")
            }
            .sensoryFeedback(.success, trigger: savedCount)
            .confirmationDialog("Reset all values to the defaults?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset Values", role: .destructive) {
                    withAnimation { calculator.reset() }
                }
            }
            .sheet(item: $shareImage, onDismiss: {
                ads.registerCompletedAction(isPremium: store.isPremium)
            }) { rendered in
                ShareImageSheet(rendered: rendered)
            }
        }
    }

    private func heroSection(_ projection: Projection, range: RangeProjection?) -> some View {
        Section {
            ProjectionOverview(projection: projection, range: range)
                .heroRow()
        }
    }

    @ViewBuilder
    private var inputSections: some View {
        @Bindable var calculator = calculator

        Section("Your Plan") {
            CurrencyInputRow(title: "Initial Investment", value: $calculator.plan.initialInvestment, systemImage: "banknote.fill", color: .green)
            CurrencyInputRow(title: "Monthly Contribution", value: $calculator.plan.monthlyContribution, systemImage: "calendar.badge.plus", color: .blue)
            YearsInputRow(years: $calculator.plan.years)
            VStack(alignment: .leading, spacing: 10) {
                NumberInputRow(title: "Expected Return", value: $calculator.plan.annualReturn, unit: "% p.a.", systemImage: "chart.line.uptrend.xyaxis", color: .teal)
                ReturnPresets(value: $calculator.plan.annualReturn)
            }
            moreOptionsToggle
        }
        .id("plan")

        if showsMoreOptions {
            Section {
                NumberInputRow(title: "Yearly Increase", value: $calculator.plan.contributionIncrease, unit: "%", systemImage: "arrow.up.forward", color: .pink)
                NumberInputRow(title: "Fund Costs (TER)", value: $calculator.plan.expenseRatio, unit: "% p.a.", systemImage: "percent", color: .red)
                NumberInputRow(title: "Inflation", value: $calculator.plan.inflation, unit: "% p.a.", systemImage: "cart.fill", color: .orange)
            } header: {
                Text("Assumptions")
            } footer: {
                Text("Yearly Increase raises your monthly contribution once a year. Fund costs are deducted from the expected return.")
            }

            SpecialPaymentsSection(plan: $calculator.plan)
        }
    }

    /// Row that reveals the advanced inputs and summarizes them while collapsed.
    private var moreOptionsToggle: some View {
        let plan = calculator.plan
        var parts = [
            String(localized: "TER \(plan.expenseRatio.percentText())"),
            String(localized: "Inflation \(plan.inflation.percentText())")
        ]
        if plan.contributionIncrease > 0 {
            parts.append(String(localized: "+\(plan.contributionIncrease.percentText()) per year"))
        }
        if plan.yearlySpecialPayment > 0 {
            parts.append(String(localized: "Special payment"))
        }
        if plan.hasPause {
            parts.append(String(localized: "Pause"))
        }
        return Button {
            withAnimation(.snappy) { showsMoreOptions.toggle() }
        } label: {
            HStack(spacing: 12) {
                IconTile(systemImage: "slider.horizontal.3", color: .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(showsMoreOptions ? "Fewer Options" : "More Options")
                        .foregroundStyle(.primary)
                    if !showsMoreOptions {
                        Text(parts.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(showsMoreOptions ? 180 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsMoreOptions ? Text("Expanded") : Text("Collapsed"))
    }

    @ViewBuilder
    private func resultSections(_ projection: Projection, range: RangeProjection?) -> some View {
        ProjectionSummarySection(projection: projection)

        // Right below the inputs, where most people scroll to.
        NativeAdSection(slot: 0)

        RangeSection(range: range)

        MilestonesSection(projection: projection)

        PortfolioSection()

        Section {
            NavigationLink {
                YearlyBreakdownView(projection: projection)
            } label: {
                Label("Year by Year", systemImage: "list.bullet.rectangle")
            }
            Button {
                payoutCapital = projection.finalValue.rounded()
                router.selectedTab = .payout
            } label: {
                Label("Plan Your Payout", systemImage: "arrow.down.forward.circle")
            }
        } footer: {
            Text("This calculation is a simplified model based on a constant return and is not investment advice. Past performance is no guarantee of future results.")
                .padding(.top, 8)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(for projection: Projection) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") {
                router.isShowingSettings = true
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu("Share", systemImage: "square.and.arrow.up") {
                Button("Share as Image", systemImage: "photo") {
                    shareTip.invalidate(reason: .actionPerformed)
                    shareImage = ShareCard(projection: projection, theme: .growth)
                        .render(currency: currency, palette: paletteOverride)
                }
                ShareLink(item: shareText(for: projection, currency: currency)) {
                    Label("Share as Text", systemImage: "text.alignleft")
                }
            }
            .popoverTip(shareTip)
            Menu("More", systemImage: "ellipsis") {
                Button("Save as Scenario", systemImage: "bookmark") {
                    guard store.hasPremiumFeatures || scenarios.count < StoreManager.freeScenarioLimit else {
                        router.isShowingPaywall = true
                        return
                    }
                    scenarioName = String(localized: "Plan from \(Date.now.formatted(date: .abbreviated, time: .shortened))")
                    isNamingScenario = true
                }
                Button("Reset Values", systemImage: "arrow.counterclockwise", role: .destructive) {
                    isConfirmingReset = true
                }
            }
        }
    }

    private func saveScenario() {
        let trimmed = scenarioName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? String(localized: "Untitled Plan") : trimmed
        modelContext.insert(Scenario(name: name, plan: calculator.plan))
        savedCount += 1
        ads.registerCompletedAction(isPremium: store.isPremium)
    }
}
