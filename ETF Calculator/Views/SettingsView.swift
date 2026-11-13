//
//  SettingsView.swift
//  ETF Calculator
//

import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(StoreManager.self) private var store
    @Environment(AdsManager.self) private var ads
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @AppStorage(Currency.storageKey) private var currencyCode = ""
    @Environment(TaxStore.self) private var taxStore
    @AppStorage(RangeProjection.volatilityKey) private var volatility = RangeProjection.defaultVolatility
    @AppStorage(Palette.storageKey) private var paletteID = ""

    @State private var isShowingPaywall = false
    @State private var isManagingSubscription = false
    @State private var isRedeemingCode = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                premiumSection

                Section {
                    Picker(selection: $currencyCode) {
                        Text("Automatic (\(Currency.regionCode))").tag("")
                        Divider()
                        ForEach(Currency.selectable, id: \.self) { code in
                            Text(Currency.displayName(for: code)).tag(code)
                        }
                    } label: {
                        SettingsLabel("Currency", systemImage: "dollarsign", color: .green)
                    }
                    .pickerStyle(.navigationLink)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        LabeledContent {
                            Image(systemName: "arrow.up.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        } label: {
                            SettingsLabel("Language", systemImage: "globe", color: .blue)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("General")
                } footer: {
                    Text("The app follows your device language. You can choose a different language for this app in the Settings app.")
                }

                appearanceSection

                taxSection

                volatilitySection

                if ads.isPrivacyOptionsRequired {
                    Section("Privacy") {
                        Button {
                            Task { await ads.presentPrivacyOptions() }
                        } label: {
                            SettingsLabel("Ad Privacy Settings", systemImage: "hand.raised.fill", color: .indigo)
                        }
                        .foregroundStyle(.primary)
                    }
                }

                #if DEBUG
                debugSection
                #endif

                Section("About") {
                    Button {
                        requestReview()
                    } label: {
                        SettingsLabel("Rate the App", systemImage: "star.fill", color: .yellow)
                    }
                    .foregroundStyle(.primary)
                    LabeledContent {
                        Text(appVersion)
                    } label: {
                        SettingsLabel("Version", systemImage: "info", color: .gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
            .offerCodeRedemption(isPresented: $isRedeemingCode) { _ in
                // The new subscription also arrives via Transaction.updates; refresh right away anyway.
                Task { await store.refreshEntitlements() }
            }
            .onChange(of: router.isShowingPaywall) { _, isShowing in
                // Locked rows request the paywall via the router; the root can't
                // present it while this sheet is up, so present it from here.
                if isShowing {
                    router.isShowingPaywall = false
                    isShowingPaywall = true
                }
            }
        }
    }

    @ViewBuilder
    private var premiumSection: some View {
        Section {
            if store.isPremium {
                HStack(spacing: 14) {
                    PremiumIcon()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium Active")
                            .font(.headline)
                        Text("Thank you for your support!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Button {
                    isManagingSubscription = true
                } label: {
                    SettingsLabel("Manage Subscription", systemImage: "creditcard.fill", color: .blue)
                }
                .foregroundStyle(.primary)
            } else {
                Button {
                    isShowingPaywall = true
                } label: {
                    HStack(spacing: 14) {
                        PremiumIcon()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Owlvest Premium")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("No ads, taxes, payout plan, market range and more")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    isRedeemingCode = true
                } label: {
                    SettingsLabel("Redeem Code", systemImage: "giftcard.fill", color: .pink)
                }
                .foregroundStyle(.primary)
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    SettingsLabel("Restore Purchases", systemImage: "arrow.clockwise", color: .gray)
                }
                .foregroundStyle(.primary)
                TrialStatusLabel()
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        @Bindable var store = store
        return Section {
            Toggle(isOn: $store.isSimulatingPremium) {
                SettingsLabel("Simulate Premium", systemImage: "hammer.fill", color: .gray)
            }
            Button {
                UserDefaults.standard.removeObject(forKey: WelcomeView.storageKey)
            } label: {
                SettingsLabel("Show Welcome on Next Launch", systemImage: "hand.wave.fill", color: .gray)
            }
            .foregroundStyle(.primary)
        } header: {
            Text(verbatim: "Debug")
        } footer: {
            Text(verbatim: "Only visible in debug builds.")
        }
    }
    #endif

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            if store.hasPremiumFeatures {
                PalettePicker(selection: $paletteID)
            } else {
                ProLockedRow(title: "Color Theme", subtitle: "Choose the colors of your cards", systemImage: "paintpalette")
            }
        } header: {
            Text("Appearance")
        } footer: {
            if store.hasPremiumFeatures {
                Text("“Automatic” gives every tab its own color. Pick a theme to use one color throughout the app.")
            }
        }
    }

    @ViewBuilder
    private var taxSection: some View {
        @Bindable var taxStore = taxStore
        let tax = taxStore.settings

        Section {
            if store.hasPremiumFeatures {
                Toggle(isOn: $taxStore.settings.isEnabled) {
                    SettingsLabel("Show After-Tax Value", systemImage: "building.columns.fill", color: .brown)
                }
                if tax.isEnabled {
                    Picker(selection: $taxStore.settings.region) {
                        ForEach(TaxRegion.allCases) { region in
                            Text(region.name).tag(region)
                        }
                    } label: {
                        SettingsLabel("Tax System", systemImage: "globe.europe.africa.fill", color: .teal)
                    }

                    switch tax.region {
                    case .germany:
                        NumberInputRow(title: "Tax Rate", value: $taxStore.settings.rate, unit: "%", fractionDigits: 0...3)
                        NumberInputRow(title: "Partial Exemption", value: $taxStore.settings.partialExemption, unit: "%")
                        CurrencyInputRow(title: "Tax-Free Allowance", value: $taxStore.settings.allowance)
                        Toggle("Advance Lump Sum (Vorabpauschale)", isOn: $taxStore.settings.includesAdvanceLumpSum)
                        if tax.includesAdvanceLumpSum {
                            Toggle("Update Base Rate Automatically", isOn: $taxStore.isBaseRateAutomatic)
                            if taxStore.isBaseRateAutomatic {
                                LabeledContent("Base Rate (Bundesbank)") {
                                    if let year = taxStore.baseRateYear {
                                        Text(verbatim: "\(tax.baseRate.percentText(2...2)) (\(year))")
                                    } else {
                                        Text(verbatim: tax.baseRate.percentText(2...2))
                                    }
                                }
                                .monospacedDigit()
                            } else {
                                NumberInputRow(title: "Base Rate", value: $taxStore.settings.baseRate, unit: "%", fractionDigits: 0...2)
                            }
                        }
                    case .unitedStates:
                        Picker("Account Type", selection: $taxStore.settings.usAccount) {
                            ForEach(USAccountType.allCases) { account in
                                Text(account.name).tag(account)
                            }
                        }
                        switch tax.usAccount {
                        case .taxable:
                            NumberInputRow(title: "Long-Term Capital Gains Rate", value: $taxStore.settings.usCapitalGainsRate, unit: "%")
                            NumberInputRow(title: "State Tax Rate", value: $taxStore.settings.usStateRate, unit: "%")
                        case .roth:
                            LabeledContent("Taxes on Withdrawal") { Text(0, format: .percent) }
                        case .traditional:
                            NumberInputRow(title: "Income Tax Rate in Retirement", value: $taxStore.settings.usIncomeRate, unit: "%")
                            NumberInputRow(title: "State Tax Rate", value: $taxStore.settings.usStateRate, unit: "%")
                        }
                    case .international:
                        NumberInputRow(title: "Tax Rate on Gains", value: $taxStore.settings.internationalRate, unit: "%")
                        CurrencyInputRow(title: "Tax-Free Allowance", value: $taxStore.settings.internationalAllowance)
                    }

                    Button("Reset to Defaults") {
                        taxStore.resetToRegionDefaults()
                    }
                }
            } else {
                ProLockedRow(title: "Taxes", subtitle: "Show your result after capital gains tax", systemImage: "building.columns")
            }
        } header: {
            Text("Taxes")
        } footer: {
            if store.hasPremiumFeatures && tax.isEnabled {
                switch tax.region {
                case .germany:
                    Text("Defaults match Germany: 26.375% (incl. solidarity surcharge), 30% partial exemption for equity ETFs and a 1,000 € yearly allowance. With the Vorabpauschale, accumulating ETFs are taxed a little every year based on the base rate published by the Federal Ministry of Finance; the rest is taxed when selling. This is a simplification, not tax advice.")
                case .unitedStates:
                    switch tax.usAccount {
                    case .taxable:
                        Text("Long-term capital gains are taxed at 0%, 15% or 20% depending on your income, plus state tax. Dividends taxed along the way are not modeled. This is a simplification, not tax advice.")
                    case .roth:
                        Text("Qualified withdrawals from Roth accounts are tax-free, since contributions were made with after-tax money. Annual contribution limits apply. This is a simplification, not tax advice.")
                    case .traditional:
                        Text("Contributions are pre-tax, so the entire withdrawal is taxed as ordinary income in retirement. Annual contribution limits apply. This is a simplification, not tax advice.")
                    }
                case .international:
                    Text("A flat tax on gains when selling. Rules vary by country — enter the rate that applies to you. This is a simplification, not tax advice.")
                }
            }
        }
    }

    @ViewBuilder
    private var volatilitySection: some View {
        Section {
            if store.hasPremiumFeatures {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent {
                        Text(verbatim: volatility.percentText(0...0))
                            .monospacedDigit()
                    } label: {
                        SettingsLabel("Volatility", systemImage: "waveform.path.ecg", color: .orange)
                    }
                    Slider(value: $volatility, in: 5...30, step: 1)
                }
            } else {
                ProLockedRow(title: "Market Fluctuations", subtitle: "Pessimistic and optimistic outcomes", systemImage: "waveform.path.ecg")
            }
        } header: {
            Text("Simulation")
        } footer: {
            if store.hasPremiumFeatures {
                Text("How much yearly returns fluctuate. Broad equity ETFs like the MSCI World have historically shown around 15%.")
            }
        }
    }
}

/// iOS Settings-style label with a white symbol on a colored rounded square.
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color

    init(_ title: LocalizedStringKey, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            IconTile(systemImage: systemImage, color: color)
        }
    }
}

/// The app icon, used on the welcome, Premium and share screens.
struct PremiumIcon: View {
    var size: CGFloat = 52

    var body: some View {
        Image("AppIconImage")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .green.opacity(0.3), radius: size * 0.15, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

/// Grid of palette swatches; an empty selection means per-tab colors.
private struct PalettePicker: View {
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            swatch(id: "", title: "Automatic") {
                // Diagonal split of the four per-tab defaults.
                AngularGradient(
                    colors: [Palette.emerald, .indigo, .sunset, .violet, .emerald].map { $0.meshColors[4] },
                    center: .center
                )
            }
            ForEach(Palette.allCases) { palette in
                swatch(id: palette.rawValue, title: palette.name) {
                    PaletteMesh(palette: palette)
                }
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func swatch(id: String, title: LocalizedStringResource, @ViewBuilder fill: () -> some View) -> some View {
        let isSelected = selection == id
        return Button {
            withAnimation(.snappy) { selection = id }
        } label: {
            VStack(spacing: 6) {
                fill()
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                    }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
