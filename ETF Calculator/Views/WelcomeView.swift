//
//  WelcomeView.swift
//  ETF Calculator
//

import SwiftUI

/// "Welcome / What's New" sheet shown on first launch and after major updates.
struct WelcomeView: View {
    /// Increase to show the sheet again after an update with notable changes.
    static let currentVersion = 2
    static let storageKey = "welcome.lastSeenVersion"

    static var needsPresentation: Bool {
        UserDefaults.standard.integer(forKey: storageKey) < currentVersion
    }

    let onContinue: () -> Void

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 18) {
                        PremiumIcon(size: 96)
                            .scaleEffect(isAnimating ? 1 : 0.6)
                            .opacity(isAnimating ? 1 : 0)

                        VStack(spacing: 8) {
                            Text("Welcome to Owlvest")
                                .font(.largeTitle.bold())
                            // Existing users know the app by its old name.
                            Text("Formerly ETF Calculator – completely rebuilt.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 12)
                    }
                    .padding(.top, 48)

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                            WelcomeFeatureRow(feature: feature)
                                .opacity(isAnimating ? 1 : 0)
                                .offset(y: isAnimating ? 0 : 16)
                                .animation(.smooth(duration: 0.6).delay(0.15 + Double(index) * 0.08), value: isAnimating)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) {
                Text("Calculations are simplified models and not investment advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: 560)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3)) { isAnimating = true }
        }
        .interactiveDismissDisabled()
    }

    private var features: [WelcomeFeature] {
        [
            WelcomeFeature(
                title: "Rebuilt for iPhone",
                message: "Fast, native and designed for iOS — with interactive charts and haptic feedback.",
                systemImage: "sparkles", color: .blue
            ),
            WelcomeFeature(
                title: "See Your Wealth Grow",
                message: "Drag across the chart to see your portfolio year by year, including milestones.",
                systemImage: "chart.line.uptrend.xyaxis", color: .green
            ),
            WelcomeFeature(
                title: "Reach Your Goal",
                message: "Find out how much you need to save each month to reach your target.",
                systemImage: "flag.checkered", color: .indigo
            ),
            WelcomeFeature(
                title: "Compare Scenarios",
                message: "Save different plans and compare them side by side.",
                systemImage: "square.stack.fill", color: .purple
            ),
            WelcomeFeature(
                title: "Premium",
                message: "Taxes, payout plan, market fluctuations, color themes — and no ads.",
                systemImage: "crown.fill", color: .orange
            )
        ]
    }
}

private struct WelcomeFeature {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    let color: Color
}

private struct WelcomeFeatureRow: View {
    let feature: WelcomeFeature

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: feature.systemImage)
                .font(.system(size: iconSize * 0.8, weight: .medium))
                .foregroundStyle(feature.color.gradient)
                .symbolRenderingMode(.hierarchical)
                .frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView {}
}
