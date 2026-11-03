//
//  PortfolioHoldingsViews.swift
//  ETF Calculator
//

import Charts
import SwiftData
import SwiftUI
import TipKit
import UniformTypeIdentifiers

// MARK: - Positions

/// Premium: positions with automatic prices, CSV import and allocation.
struct HoldingsSection: View {
    /// Called with the new total after prices were refreshed or positions imported.
    let onTotalChanged: (Double) -> Void

    @Environment(StoreManager.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currencyCode) private var currency
    @Query(sort: \Holding.value, order: .reverse) private var holdings: [Holding]

    @State private var editedHolding: Holding?
    @State private var isAddingHolding = false
    @State private var isImporting = false
    @State private var isRefreshing = false
    @State private var groupsByAssetClass = false

    static let palette: [Color] = [.green, .blue, .orange, .purple, .pink, .teal, .yellow, .indigo, .red, .mint]

    static func color(for index: Int) -> Color {
        palette[index % palette.count]
    }

    var body: some View {
        Section {
            if store.hasPremiumFeatures {
                if !holdings.isEmpty {
                    Picker("Group By", selection: $groupsByAssetClass) {
                        Text("Positions").tag(false)
                        Text("Asset Classes").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    AllocationChart(holdings: holdings, groupsByAssetClass: groupsByAssetClass)
                        .padding(.vertical, 8)

                    ForEach(holdings) { holding in
                        Button {
                            editedHolding = holding
                        } label: {
                            HoldingRow(holding: holding)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(holdings[index]) }
                    }
                }

                Button("Add Position", systemImage: "plus.circle.fill") {
                    isAddingHolding = true
                }
                TipView(BrokerImportTip())
                    .tipBackground(Color.clear)
                Button("Import from Broker (CSV)", systemImage: "square.and.arrow.down") {
                    BrokerImportTip().invalidate(reason: .actionPerformed)
                    isImporting = true
                }
                if QuoteService.isAvailable, holdings.contains(where: { !$0.symbol.isEmpty }) {
                    Button {
                        Task { await refreshPrices(force: true) }
                    } label: {
                        HStack {
                            Label("Update Prices", systemImage: "arrow.clockwise")
                            if isRefreshing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshing)
                }
            } else {
                ProLockedRow(title: "Positions & Allocation", subtitle: "Import from your broker, automatic prices", systemImage: "chart.pie")
            }
        } header: {
            Text("Positions")
        } footer: {
            if store.hasPremiumFeatures {
                if QuoteService.isAvailable {
                    if let lastRefresh = PortfolioPricing.lastRefresh {
                        Text("Prices are delayed and updated automatically. Last update: \(lastRefresh.formatted(date: .abbreviated, time: .shortened)).")
                    } else {
                        Text("Add an ISIN and the number of shares — prices then update automatically.")
                    }
                } else {
                    Text("Export the portfolio overview from your broker or bank as a CSV file and import it here. Prices can be entered per position.")
                }
            }
        }
        .sheet(item: $editedHolding) { holding in
            HoldingEditor(holding: holding, colorIndex: holding.colorIndex)
        }
        .sheet(isPresented: $isAddingHolding) {
            HoldingEditor(holding: nil, colorIndex: holdings.count)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]) { result in
            switch result {
            case .success(let url): router.openPortfolioFile(url)
            case .failure(let error): router.importError = error.localizedDescription
            }
        }
        .task {
            guard store.hasPremiumFeatures else { return }
            await refreshPrices(force: false)
        }
    }

    private func refreshPrices(force: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        if let total = try? await PortfolioPricing.refresh(holdings: holdings, force: force) {
            onTotalChanged(total)
        }
    }
}

private struct HoldingRow: View {
    let holding: Holding

    @Environment(\.currencyCode) private var currency

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(HoldingsSection.color(for: holding.colorIndex).gradient)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name)
                    .lineLimit(1)
                if holding.isPriced {
                    Text("\(holding.shares.formatted(.number.precision(.fractionLength(0...4)))) × \(holding.price.formatted(.currency(code: currency)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !holding.isin.isEmpty {
                    Text(verbatim: holding.isin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(holding.value, format: .currency(code: currency))
        }
        .monospacedDigit()
    }
}

private struct AllocationChart: View {
    let holdings: [Holding]
    let groupsByAssetClass: Bool

    @Environment(\.currencyCode) private var currency

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let value: Double
        let color: Color
    }

    private var slices: [Slice] {
        if groupsByAssetClass {
            let grouped = Dictionary(grouping: holdings, by: \.assetClass)
            return grouped.map { assetClass, items in
                let index = AssetClass.allCases.firstIndex(of: assetClass) ?? 0
                return Slice(id: assetClass.rawValue, name: String(localized: assetClass.name), value: items.reduce(0) { $0 + $1.value }, color: HoldingsSection.color(for: index))
            }
            .sorted { $0.value > $1.value }
        }
        return holdings.map { Slice(id: "\($0.persistentModelID)", name: $0.name, value: $0.value, color: HoldingsSection.color(for: $0.colorIndex)) }
    }

    var body: some View {
        let slices = slices
        let total = slices.reduce(0) { $0 + $1.value }
        HStack(spacing: 20) {
            Chart(slices) { slice in
                SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(slice.color.gradient)
            }
            .chartLegend(.hidden)
            .frame(width: 120, height: 120)
            .overlay {
                Text(total, format: .currency(code: currency).notation(.compactName))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 20)
            }
            .animation(.smooth, value: groupsByAssetClass)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(slices.prefix(6)) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(total > 0 ? slice.value / total : 0, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor

/// Adds or edits a position, including ISIN lookup for automatic prices.
private struct HoldingEditor: View {
    let holding: Holding?
    let colorIndex: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyCode) private var currency

    @State private var name = ""
    @State private var isin = ""
    @State private var symbol = ""
    @State private var shares = 0.0
    @State private var price = 0.0
    @State private var manualValue = 0.0
    @State private var expenseRatio = 0.0
    @State private var assetClass = AssetClass.world
    @State private var targetWeight = 0.0
    @State private var costBasis = 0.0
    @State private var isLookingUp = false
    @State private var lookupMessage: String?

    private var computedValue: Double { shares > 0 && price > 0 ? shares * price : manualValue }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. MSCI World", text: $name)
                    HStack {
                        TextField("ISIN", text: $isin)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .monospaced()
                        if QuoteService.isAvailable {
                            Button {
                                Task { await lookUp() }
                            } label: {
                                if isLookingUp { ProgressView() } else { Text("Look Up") }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isin.count != 12 || isLookingUp)
                        }
                    }
                    if let lookupMessage {
                        Text(lookupMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NumberInputRow(title: "Shares", value: $shares, unit: "", fractionDigits: 0...4, systemImage: "number", color: .blue)
                    CurrencyInputRow(title: "Price per Share", value: $price, systemImage: "eurosign", color: .green)
                    if shares == 0 || price == 0 {
                        CurrencyInputRow(title: "Value", value: $manualValue, systemImage: "briefcase.fill", color: .brown)
                    }
                    LabeledContent("Position Value") {
                        Text(computedValue, format: .currency(code: currency))
                            .fontWeight(.semibold)
                    }
                    .monospacedDigit()
                    CurrencyInputRow(title: "Paid In (Cost Basis)", value: $costBasis, systemImage: "cart.fill", color: .orange)
                } footer: {
                    Text("Enter shares and price, or just the total value of the position. The cost basis is what you paid in total, including fees.")
                }

                Section("Details") {
                    NumberInputRow(title: "Fund Costs (TER)", value: $expenseRatio, unit: "% p.a.", systemImage: "percent", color: .red)
                    Picker(selection: $assetClass) {
                        ForEach(AssetClass.allCases) { assetClass in
                            Text(assetClass.name).tag(assetClass)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(systemImage: "globe.americas.fill", color: .teal)
                            Text("Asset Class")
                        }
                    }
                    NumberInputRow(title: "Target Share", value: $targetWeight, unit: "%", systemImage: "target", color: .purple)
                }

                if let holding {
                    Section {
                        Button("Delete Position", role: .destructive) {
                            modelContext.delete(holding)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(holding == nil ? "Add Position" : "Edit Position")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm, action: save)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let holding else { return }
        name = holding.name
        isin = holding.isin
        symbol = holding.symbol
        shares = holding.shares
        price = holding.price
        manualValue = holding.isPriced ? 0 : holding.value
        expenseRatio = holding.expenseRatio
        assetClass = holding.assetClass
        targetWeight = holding.targetWeight
        costBasis = holding.costBasis
    }

    private func lookUp() async {
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let listing = try await QuoteService.lookup(isin: isin.uppercased(), preferredCurrency: currency)
            symbol = listing.symbol
            if name.isEmpty { name = listing.name }
            if let listingPrice = listing.price { price = listingPrice }
            lookupMessage = String(localized: "Found \(listing.name) (\(listing.symbol)).")
        } catch {
            lookupMessage = error.localizedDescription
        }
    }

    private func save() {
        UIApplication.shared.dismissKeyboard()
        Task { @MainActor in
            // Number fields commit on end of editing.
            try? await Task.sleep(for: .milliseconds(80))
            let target = holding ?? {
                let new = Holding(name: "", value: 0, colorIndex: colorIndex)
                modelContext.insert(new)
                return new
            }()
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            target.name = trimmed.isEmpty ? String(localized: "Position") : trimmed
            target.isin = isin.uppercased().trimmingCharacters(in: .whitespaces)
            target.symbol = symbol
            target.shares = shares
            target.price = price
            target.value = computedValue
            target.expenseRatio = expenseRatio
            target.assetClass = assetClass
            target.targetWeight = targetWeight
            target.costBasis = costBasis
            dismiss()
        }
    }
}

// MARK: - CSV import

struct ImportPreview: View {
    let result: PortfolioCSVImporter.Result
    let onImported: (Double) -> Void

    private var positions: [PortfolioCSVImporter.Position] { result.positions }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyCode) private var currency
    @Environment(CalculatorModel.self) private var calculator
    @Query private var holdings: [Holding]
    @Query private var existingDividends: [Dividend]

    @State private var selection: Set<UUID> = []
    @State private var replacesExisting = true
    @State private var isImporting = false

    var body: some View {
        let selected = positions.filter { selection.contains($0.id) }
        NavigationStack {
            List {
                Section {
                    ForEach(positions) { position in
                        Button {
                            if selection.contains(position.id) { selection.remove(position.id) } else { selection.insert(position.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(position.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(position.id) ? Color.accentColor : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(position.name).lineLimit(1)
                                    Text(verbatim: [position.isin, position.symbol].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(position.value, format: .currency(code: currency))
                                    .monospacedDigit()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Found \(positions.count) Positions")
                } footer: {
                    let cost = selected.reduce(0) { $0 + $1.costBasis }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total: \(selected.reduce(0) { $0 + $1.value }.formatted(.currency(code: currency)))")
                        if cost > 0 {
                            Text("Paid in: \(cost.formatted(.currency(code: currency)))")
                        }
                    }
                    .monospacedDigit()
                }

                if result.isFromTransactions {
                    Section {
                        Label {
                            Text("Calculated from your transactions. Values are based on the last purchase prices — update prices afterwards for current values.")
                        } icon: {
                            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                        }
                        .font(.footnote)
                        if !result.dividends.isEmpty {
                            Label("\(result.dividends.count) distributions are imported too.", systemImage: "banknote")
                                .font(.footnote)
                        }
                        if let first = result.firstTransactionDate {
                            Label("First purchase on \(first.formatted(date: .abbreviated, time: .omitted)).", systemImage: "calendar")
                                .font(.footnote)
                        }
                    }
                }

                Section {
                    Toggle("Replace Existing Positions", isOn: $replacesExisting)
                } footer: {
                    Text("Positions with the same ISIN are always updated. The total is recorded as today's portfolio value.")
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", systemImage: "checkmark", role: .confirm) {
                        Task { await importSelected(selected) }
                    }
                    .disabled(selected.isEmpty || isImporting)
                }
            }
            .onAppear { selection = Set(positions.map(\.id)) }
        }
    }

    private func importSelected(_ selected: [PortfolioCSVImporter.Position]) async {
        isImporting = true
        defer { isImporting = false }
        let importedISINs = Set(selected.map(\.isin).filter { !$0.isEmpty })
        if replacesExisting {
            for holding in holdings where holding.isin.isEmpty || !importedISINs.contains(holding.isin) {
                modelContext.delete(holding)
            }
        }
        var colorIndex = replacesExisting ? 0 : holdings.count
        var updated: [Holding] = []
        for position in selected {
            let existing = position.isin.isEmpty ? nil : holdings.first { $0.isin == position.isin }
            let holding = existing ?? {
                let new = Holding(name: position.name, value: position.value, colorIndex: colorIndex)
                colorIndex += 1
                modelContext.insert(new)
                return new
            }()
            holding.name = position.name
            holding.isin = position.isin
            holding.shares = position.shares
            holding.price = position.price
            holding.value = position.value
            holding.costBasis = position.costBasis
            holding.priceUpdatedAt = .now
            updated.append(holding)
        }
        // Remember the import's start and monthly rate as suggestions for the plan comparison.
        if calculator.portfolioPlan == nil, let first = result.firstTransactionDate {
            calculator.planStartDate = first
        }
        if let monthly = result.typicalMonthlyPurchase {
            calculator.suggestedMonthlyContribution = monthly
        }
        // Dividends from a transaction export, skipping ones already recorded.
        for dividend in result.dividends where !existingDividends.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: dividend.date) && abs($0.amount - dividend.amount) < 0.005
        }) {
            modelContext.insert(Dividend(date: dividend.date, amount: dividend.amount, note: dividend.note))
        }
        // Resolve exchange symbols so prices update automatically from now on.
        if QuoteService.isAvailable {
            for holding in updated where holding.symbol.isEmpty && !holding.isin.isEmpty {
                if let listing = try? await QuoteService.lookup(isin: holding.isin, preferredCurrency: currency) {
                    holding.symbol = listing.symbol
                }
            }
        }
        onImported(selected.reduce(0) { $0 + $1.value })
        dismiss()
    }
}

// MARK: - Cost check

/// Premium: weighted TER and what fees cost until the end of the plan.
struct CostCheckSection: View {
    let plan: SavingsPlan
    let startDate: Date

    @Environment(StoreManager.self) private var store
    @Environment(\.currencyCode) private var currency
    @Query private var holdings: [Holding]

    var body: some View {
        let total = holdings.reduce(0) { $0 + $1.value }
        let withCosts = holdings.filter { $0.expenseRatio > 0 }
        if store.hasPremiumFeatures, total > 0, !withCosts.isEmpty {
            let weightedTER = holdings.reduce(0) { $0 + $1.value * $1.expenseRatio } / total
            let elapsedYears = SavingsPlan.monthsElapsed(from: startDate, to: .now) / 12
            let remainingYears = max(1, plan.years - elapsedYears)
            let costs = Self.costUntilEnd(total: total, monthly: plan.monthlyContribution, years: remainingYears, annualReturn: plan.annualReturn, ter: weightedTER)

            Section {
                LabeledContent("Weighted TER") {
                    Text("\(weightedTER.percentText(2...2)) p.a.")
                }
                LabeledContent("Costs per Year Today") {
                    Text(total * weightedTER / 100, format: .currency(code: currency))
                }
                LabeledContent {
                    Text(costs, format: .currency(code: currency))
                        .fontWeight(.semibold)
                } label: {
                    Text("Costs Until Plan End")
                    Text("^[\(remainingYears) Year](inflect: true), including lost returns")
                }
                if let mostExpensive = holdings.max(by: { $0.expenseRatio < $1.expenseRatio }), mostExpensive.expenseRatio > weightedTER + 0.1 {
                    Label {
                        Text("\(mostExpensive.name) is your most expensive position (\(mostExpensive.expenseRatio.percentText(2...2))). Cheaper alternatives often exist.")
                    } icon: {
                        Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    }
                    .font(.footnote)
                }
            } header: {
                Text("Cost Check")
            }
            .monospacedDigit()
        }
    }

    /// Difference between growing the portfolio with and without fund costs.
    static func costUntilEnd(total: Double, monthly: Double, years: Int, annualReturn: Double, ter: Double) -> Double {
        func grow(_ rate: Double) -> Double {
            let factor = 1 + rate / 100 / 12
            var balance = total
            for _ in 0..<(years * 12) { balance = (balance + monthly) * factor }
            return balance
        }
        return max(0, grow(annualReturn) - grow(annualReturn - ter))
    }
}

// MARK: - Rebalancing

/// Premium: shows target vs. actual and splits the next contribution so the
/// portfolio moves towards the targets without selling anything.
struct RebalancingSection: View {
    let monthlyContribution: Double

    @Environment(StoreManager.self) private var store
    @Environment(\.currencyCode) private var currency
    @Query(sort: \Holding.value, order: .reverse) private var holdings: [Holding]

    var body: some View {
        let targeted = holdings.filter { $0.targetWeight > 0 }
        let total = holdings.reduce(0) { $0 + $1.value }
        if store.hasPremiumFeatures, !targeted.isEmpty, total > 0 {
            let allocation = Self.allocate(monthlyContribution, holdings: targeted, total: total)
            let targetSum = targeted.reduce(0) { $0 + $1.targetWeight }

            Section {
                ForEach(targeted) { holding in
                    let actual = holding.value / total * 100
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(holding.name).lineLimit(1)
                            Spacer()
                            Text(verbatim: "\(actual.percentText(0...0)) / \(holding.targetWeight.percentText(0...0))")
                                .foregroundStyle(.secondary)
                        }
                        Gauge(value: min(actual, holding.targetWeight * 2), in: 0...max(holding.targetWeight * 2, 1)) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(HoldingsSection.color(for: holding.colorIndex))
                        if let amount = allocation[holding.persistentModelID], amount >= 1 {
                            Text("Next contribution: \(amount.formatted(.currency(code: currency).precision(.fractionLength(0))))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Target Allocation")
            } footer: {
                if abs(targetSum - 100) > 0.5 {
                    Text("Your targets add up to \(targetSum.percentText(0...0)). Set them so they add up to \(100.0.percentText(0...0)).")
                } else {
                    Text("Your next monthly contribution of \(monthlyContribution.formatted(.currency(code: currency).precision(.fractionLength(0)))) is split so you move towards your targets without selling.")
                }
            }
            .monospacedDigit()
        }
    }

    /// Buy-only rebalancing: fills the largest gaps to the targets first.
    static func allocate(_ amount: Double, holdings: [Holding], total: Double) -> [PersistentIdentifier: Double] {
        let targetSum = holdings.reduce(0) { $0 + $1.targetWeight }
        guard targetSum > 0, amount > 0 else { return [:] }
        let newTotal = total + amount
        let gaps = holdings.map { holding in
            (holding.persistentModelID, max(0, newTotal * holding.targetWeight / targetSum - holding.value))
        }
        let gapSum = gaps.reduce(0) { $0 + $1.1 }
        guard gapSum > 0 else {
            // Already on target: split by target weights.
            return Dictionary(uniqueKeysWithValues: holdings.map { ($0.persistentModelID, amount * $0.targetWeight / targetSum) })
        }
        return Dictionary(uniqueKeysWithValues: gaps.map { ($0.0, amount * $0.1 / gapSum) })
    }
}

// MARK: - Dividends

/// Premium: record distributions and see yearly totals.
struct DividendsSection: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currencyCode) private var currency
    @Query(sort: \Dividend.date, order: .reverse) private var dividends: [Dividend]
    @State private var isAdding = false

    var body: some View {
        Section {
            if store.hasPremiumFeatures {
                let calendar = Calendar.current
                let thisYear = dividends.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .year) }.reduce(0) { $0 + $1.amount }
                let yearAgo = calendar.date(byAdding: .year, value: -1, to: .now) ?? .now
                let trailing = dividends.filter { $0.date >= yearAgo }.reduce(0) { $0 + $1.amount }

                if !dividends.isEmpty {
                    LabeledContent("This Year") { Text(thisYear, format: .currency(code: currency)) }
                    LabeledContent("Last 12 Months") { Text(trailing, format: .currency(code: currency)) }
                    LabeledContent("Per Month on Average") { Text(trailing / 12, format: .currency(code: currency)) }
                    ForEach(dividends.prefix(10)) { dividend in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dividend.note.isEmpty ? String(localized: "Distribution") : dividend.note)
                                Text(dividend.date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(dividend.amount, format: .currency(code: currency))
                                .foregroundStyle(.green)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(dividends[index]) }
                    }
                }
                Button("Add Distribution", systemImage: "plus.circle.fill") {
                    isAdding = true
                }
            } else {
                ProLockedRow(title: "Dividends", subtitle: "Track distributions and yearly income", systemImage: "banknote")
            }
        } header: {
            Text("Dividends")
        }
        .monospacedDigit()
        .sheet(isPresented: $isAdding) {
            AddDividendView()
                .presentationDetents([.medium])
        }
    }
}

private struct AddDividendView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var amount = 0.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                CurrencyInputRow(title: "Amount", value: $amount, systemImage: "banknote.fill", color: .green)
                TextField("Note, e.g. Vanguard FTSE All-World", text: $note)
            }
            .navigationTitle("Add Distribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        UIApplication.shared.dismissKeyboard()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(80))
                            if amount > 0 {
                                modelContext.insert(Dividend(date: date, amount: amount, note: note.trimmingCharacters(in: .whitespaces)))
                            }
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Celebration

/// Shown when the real portfolio crosses a round amount for the first time.
struct MilestoneCelebrationView: View {
    let amount: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.currencyCode) private var currency
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.mint, .green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .shadow(color: .green.opacity(0.4), radius: 20, y: 8)
                Image(systemName: amount >= 1_000_000 ? "crown.fill" : amount >= 100_000 ? "trophy.fill" : "star.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isAnimating)
            }
            VStack(spacing: 8) {
                Text("Milestone Reached!")
                    .font(.title.bold())
                Text("Your portfolio has passed \(amount.formatted(.currency(code: currency).precision(.fractionLength(0)))). Keep it up!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(28)
        .sensoryFeedback(.success, trigger: isAnimating)
        .onAppear { isAnimating = true }
    }
}
