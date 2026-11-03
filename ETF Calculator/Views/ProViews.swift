//
//  ProViews.swift
//  ETF Calculator
//

import SwiftUI

extension EnvironmentValues {
    /// Tax assumptions configured in Settings.
    @Entry var taxSettings = TaxSettings()
    /// Annual volatility (in percent) used for the Monte Carlo range.
    @Entry var volatility: Double = 15
}

/// Small capsule marking a Premium feature.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.gradient, in: .capsule)
            .accessibilityLabel("Premium feature")
    }
}

/// A row teasing a Premium feature; tapping it opens the paywall.
struct ProLockedRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String

    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.isShowingPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ProBadge()
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Full-screen teaser for a Premium-only tab.
struct ProTeaserView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label {
                HStack(spacing: 8) {
                    Text(title)
                    ProBadge()
                }
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }
        } description: {
            Text(message)
        } actions: {
            Button("Unlock Premium", systemImage: "sparkles") {
                router.isShowingPaywall = true
            }
            .buttonStyle(.glassProminent)
            .tint(.orange)
            TrialOfferButton()
        }
    }
}

/// Opt-in rewarded ad that unlocks Premium features for one hour (limited per day).
/// Only offered when an ad is ready and no trial or subscription is active.
struct TrialOfferButton: View {
    var onUnlocked: () -> Void = {}

    @Environment(AdsManager.self) private var ads
    @Environment(StoreManager.self) private var store

    var body: some View {
        if ads.isRewardedAdReady, !store.hasPremiumFeatures, store.remainingTrialsToday > 0 {
            Button {
                ads.showRewardedAd {
                    store.startTrial()
                    onUnlocked()
                }
            } label: {
                Label("Watch an Ad to Try Premium for 1 Hour", systemImage: "play.rectangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.glass)
        }
    }
}

/// Shown while a 24-hour trial is running.
struct TrialStatusLabel: View {
    @Environment(StoreManager.self) private var store

    var body: some View {
        if store.isTrialActive, !store.isPremium, let until = store.trialUnlockedUntil {
            Label("Premium trial until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "timer")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.orange)
        }
    }
}
