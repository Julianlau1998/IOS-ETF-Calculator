//
//  PaywallView.swift
//  ETF Calculator
//

import StoreKit
import SwiftUI

/// Two-step Premium flow: benefits first, then the subscription options.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    /// Screenshot runs (`-screenshotScreen plans`) open the plans directly.
    @State private var isShowingPlans = DemoData.screen == "plans"
    #else
    @State private var isShowingPlans = false
    #endif

    var body: some View {
        NavigationStack {
            PaywallBenefitsStep {
                isShowingPlans = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingPlans) {
                PaywallPlansStep {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Step 1

private struct PaywallBenefitsStep: View {
    let onContinue: () -> Void

    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    PremiumIcon(size: 92)

                    VStack(spacing: 8) {
                        Text("Owlvest Premium")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Plan your wealth with more precision — and without ads.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(Array(PremiumBenefit.all.enumerated()), id: \.offset) { _, benefit in
                        PremiumBenefitCard(benefit: benefit)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background {
            // Warm glow matching the Premium accent.
            LinearGradient(colors: [.orange.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                StepIndicator(step: 1)
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.orange)

                TrialOfferButton {
                    dismiss()
                }
                Button("Restore Purchases") {
                    Task { await store.restorePurchases() }
                }
                .font(.footnote)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
        }
    }
}

private struct PremiumBenefit {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let color: Color

    static let all: [PremiumBenefit] = [
        PremiumBenefit(title: "No Ads", subtitle: "A calm experience without interruptions", systemImage: "rectangle.slash", color: .blue),
        PremiumBenefit(title: "After Taxes", subtitle: "Taxes for Germany, the US and other countries", systemImage: "building.columns.fill", color: .brown),
        PremiumBenefit(title: "Payout Plan", subtitle: "See how long your money lasts in retirement", systemImage: "arrow.down.forward.circle.fill", color: .orange),
        PremiumBenefit(title: "Market Fluctuations", subtitle: "Pessimistic and optimistic outcomes from 500 simulations", systemImage: "waveform.path.ecg", color: .red),
        PremiumBenefit(title: "Color Themes", subtitle: "Make the app yours with seven color worlds", systemImage: "paintpalette.fill", color: .pink),
        PremiumBenefit(title: "Unlimited Scenarios", subtitle: "Save and compare as many plans as you like", systemImage: "square.stack.fill", color: .purple),
        PremiumBenefit(title: "CSV Export", subtitle: "Take the yearly table to Numbers or Excel", systemImage: "tablecells.fill", color: .green)
    ]
}

private struct PremiumBenefitCard: View {
    let benefit: PremiumBenefit

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: benefit.systemImage, color: benefit.color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.headline)
                Text(benefit.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Step 2

private struct PaywallPlansStep: View {
    let onPurchased: () -> Void

    @Environment(StoreManager.self) private var store

    var body: some View {
        SubscriptionStoreView(productIDs: StoreManager.productIDs) {
            VStack(spacing: 12) {
                PremiumIcon(size: 64)
                Text("Choose Your Plan")
                    .font(.title.bold())
                Text("Cancel anytime in the App Store settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                StepIndicator(step: 2)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .policies)
        .storeButton(.hidden, for: .cancellation)
        .tint(.orange)
        .navigationBarTitleDisplayMode(.inline)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                await store.refreshEntitlements()
                onPurchased()
            }
        }
    }
}

/// "● ○" style progress for the two paywall steps.
private struct StepIndicator: View {
    let step: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...2, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Color.orange : Color.secondary.opacity(0.3))
                    .frame(width: index == step ? 20 : 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step) of 2")
    }
}

#Preview {
    PaywallView()
        .environment(StoreManager())
}
