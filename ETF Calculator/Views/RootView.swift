//
//  RootView.swift
//  ETF Calculator
//

import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(StoreManager.self) private var store
    @Environment(AdsManager.self) private var ads
    @Environment(CalculatorModel.self) private var calculator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PortfolioEntry.date) private var portfolioEntries: [PortfolioEntry]
    @AppStorage("goal.target") private var goalTarget = 100_000.0
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(Currency.storageKey) private var currencyCode = ""
    @Environment(TaxStore.self) private var taxStore
    @AppStorage(RangeProjection.volatilityKey) private var volatility = RangeProjection.defaultVolatility
    @AppStorage(Palette.storageKey) private var paletteID = ""

    /// The chosen palette only applies while the subscription is active.
    private var paletteOverride: Palette? {
        store.hasPremiumFeatures ? Palette(rawValue: paletteID) : nil
    }

    /// Screenshot runs keep the full tab bar so it never covers content.
    private var keepsTabBarExpanded: Bool {
        #if DEBUG
        DemoData.isRequested
        #else
        false
        #endif
    }

    private var isCoveredBySheet: Bool {
        router.isShowingWelcome || router.isShowingPaywall || router.isShowingSettings
    }

    /// Everything the widgets display; changes trigger a widget refresh.
    private struct WidgetInputs: Equatable {
        let plan: SavingsPlan
        let currency: String
        let startDate: Date?
        let latestValue: Double?
        let goalTarget: Double
    }

    private var widgetInputs: WidgetInputs {
        WidgetInputs(
            plan: calculator.plan,
            currency: Currency.resolved(currencyCode),
            startDate: calculator.portfolioComparisonPlan?.start,
            latestValue: portfolioEntries.last?.value,
            goalTarget: goalTarget
        )
    }

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Calculator", systemImage: "chart.line.uptrend.xyaxis", value: .calculator) {
                CalculatorView()
            }
            Tab("Goal", systemImage: "flag.checkered", value: .goal) {
                GoalView()
            }
            Tab("Payout", systemImage: "arrow.down.forward.circle", value: .payout) {
                PayoutView()
            }
            Tab("Portfolio", systemImage: "briefcase", value: .portfolio) {
                PortfolioView()
            }
            Tab("Scenarios", systemImage: "square.stack", value: .scenarios) {
                ScenariosView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(keepsTabBarExpanded ? .never : .onScrollDown)
        .environment(\.currencyCode, Currency.resolved(currencyCode))
        .environment(\.taxSettings, taxStore.settings)
        .environment(\.volatility, volatility)
        .environment(\.paletteOverride, paletteOverride)
        .sheet(isPresented: $router.isShowingSettings) {
            SettingsView()
                .environment(\.currencyCode, Currency.resolved(currencyCode))
        }
        .sheet(isPresented: $router.isShowingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $router.isShowingWelcome) {
            WelcomeView {
                UserDefaults.standard.set(WelcomeView.currentVersion, forKey: WelcomeView.storageKey)
                router.isShowingWelcome = false
            }
        }
        .onChange(of: widgetInputs, initial: true) { _, inputs in
            WidgetSync.update(
                plan: inputs.plan,
                currency: inputs.currency,
                planStartDate: inputs.startDate,
                latestPortfolioValue: inputs.latestValue,
                goalTarget: inputs.goalTarget
            )
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ads.refreshNativeAdsIfNeeded(isPremium: store.isPremium)
                ads.appDidBecomeActive(
                    isPremium: store.isPremium,
                    isBlocked: router.isShowingWelcome || router.isShowingPaywall || router.isKeyboardVisible
                )
            case .background:
                ads.appDidEnterBackground()
            default:
                break
            }
        }
        .task(id: isCoveredBySheet) {
            if isCoveredBySheet {
                AppTips.isAppVisible = false
            } else {
                // Give a dismissing sheet time to slide away before tips may appear.
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                AppTips.isAppVisible = true
            }
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            router.isShowingSettings = false
            router.openPortfolioFile(url)
        }
        .onChange(of: router.selectedTab) {
            ads.registerTabSwitch(isPremium: store.isPremium)
        }
        .task {
            await store.refreshEntitlements()
        }
        #if DEBUG
        .task {
            if DemoData.isRequested {
                DemoData.seed(context: modelContext, calculator: calculator)
                router.selectedTab = DemoData.tab
                if DemoData.screen == "paywall" || DemoData.screen == "plans" {
                    router.isShowingPaywall = true
                }
            }
        }
        #endif
        .task {
            await taxStore.refreshBaseRate()
        }
        .task(id: store.trialUnlockedUntil) {
            await store.waitForTrialEnd()
        }
        .task(id: router.isShowingWelcome) {
            // Ask for ad consent only after the welcome screen is gone,
            // so the first thing people see is the app, not a dialog.
            guard !router.isShowingWelcome else { return }
            // Let a dismissing sheet finish its animation before presenting the consent form.
            try? await Task.sleep(for: .milliseconds(600))
            await ads.start(isPremium: store.isPremium)
        }
        .task {
            // Select the whole value when a number field is tapped, so typing replaces it.
            for await notification in NotificationCenter.default.notifications(named: UITextField.textDidBeginEditingNotification) {
                guard let field = notification.object as? UITextField else { continue }
                Task { @MainActor in field.selectAll(nil) }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                router.isKeyboardVisible = true
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                router.isKeyboardVisible = false
            }
        }
    }
}
