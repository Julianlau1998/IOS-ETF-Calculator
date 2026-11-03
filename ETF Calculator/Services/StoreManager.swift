//
//  StoreManager.swift
//  ETF Calculator
//

import Foundation
import Observation
import StoreKit

/// Tracks the ad-free "Premium" subscription using StoreKit 2.
@Observable
@MainActor
final class StoreManager {
    /// Product identifiers configured in App Store Connect (same subscription group).
    static let productIDs = [
        "app.etfcalculator.premium.monthly",
        "app.etfcalculator.premium.yearly"
    ]

    /// Scenarios that can be saved without a subscription.
    static let freeScenarioLimit = 3

    /// Verified subscription state from StoreKit (cached for a fast launch).
    private(set) var hasActiveSubscription = UserDefaults.standard.bool(forKey: "isPremium") {
        didSet {
            UserDefaults.standard.set(hasActiveSubscription, forKey: "isPremium")
            WidgetSync.premiumChanged(isPremium)
        }
    }

    #if DEBUG
    /// Debug-only switch in Settings to try Premium features without buying.
    var isSimulatingPremium = UserDefaults.standard.bool(forKey: "debug.simulatePremium") {
        didSet {
            UserDefaults.standard.set(isSimulatingPremium, forKey: "debug.simulatePremium")
            WidgetSync.premiumChanged(isPremium)
        }
    }

    var isPremium: Bool { hasActiveSubscription || isSimulatingPremium }
    #else
    var isPremium: Bool { hasActiveSubscription }
    #endif

    /// Premium features unlocked for a limited time by watching a rewarded ad.
    /// Ads stay on during the trial; only the subscription removes them.
    private(set) var trialUnlockedUntil = UserDefaults.standard.object(forKey: "trialUnlockedUntil") as? Date {
        didSet { UserDefaults.standard.set(trialUnlockedUntil, forKey: "trialUnlockedUntil") }
    }

    /// One rewarded ad unlocks Premium features for an hour…
    static let trialDuration: TimeInterval = 60 * 60
    /// …at most this many times per day, so ads don't replace the subscription.
    static let trialsPerDay = 3

    /// Start dates of trials, used for the daily limit.
    private var trialStarts: [Date] = (UserDefaults.standard.array(forKey: "trialStarts") as? [Date]) ?? [] {
        didSet { UserDefaults.standard.set(trialStarts, forKey: "trialStarts") }
    }

    var isTrialActive: Bool {
        _ = trialRevision
        guard let trialUnlockedUntil else { return false }
        return trialUnlockedUntil > .now
    }

    /// Trials left today (resets at midnight).
    var remainingTrialsToday: Int {
        let today = trialStarts.filter { Calendar.current.isDateInToday($0) }.count
        return max(0, Self.trialsPerDay - today)
    }

    /// Gate for Premium *features* (taxes, payout, themes, …).
    var hasPremiumFeatures: Bool { isPremium || isTrialActive }

    /// Waits until the running trial ends and then notifies observers,
    /// so locked features close even while the app stays open.
    func waitForTrialEnd() async {
        guard let until = trialUnlockedUntil, until > .now else { return }
        try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow + 1))
        guard !Task.isCancelled else { return }
        trialRevision += 1
    }

    /// Bumped when a trial ends so views depending on `isTrialActive` update.
    private var trialRevision = 0

    func startTrial() {
        guard remainingTrialsToday > 0 else { return }
        trialStarts = trialStarts.filter { Calendar.current.isDateInToday($0) } + [.now]
        trialUnlockedUntil = Date.now.addingTimeInterval(Self.trialDuration)
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        // Purchases made on other devices, renewals, refunds, Ask to Buy, …
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlements()
            }
        }
    }

    /// Re-derives premium status from the verified current entitlements.
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
            await transaction.finish()
        }
        hasActiveSubscription = active
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
