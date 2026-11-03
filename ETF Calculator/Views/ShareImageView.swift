//
//  ShareImageView.swift
//  ETF Calculator
//

import SwiftUI

/// Portrait card that is rendered to an image for sharing.
struct ShareCard: View {
    let projection: Projection
    let theme: CardTheme

    @Environment(\.currencyCode) private var currency

    var body: some View {
        let plan = projection.plan
        HeroCard(theme: theme) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    PremiumIcon(size: 34)
                    Text("My ETF Savings Plan")
                        .font(.headline)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Final Value · ^[\(plan.years) Year](inflect: true)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .textCase(.uppercase)
                    Text(projection.finalValue, format: .currency(code: currency).precision(.fractionLength(0)))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    CardBadge {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                            Text(projection.totalGains, format: .wholeCurrency(currency).sign(strategy: .always()))
                            Text("returns")
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .monospacedDigit()
                    }
                }

                GrowthChart(projection: projection, selectedYear: .constant(nil), animatesIn: false)

                // Fixed-height separators: `Divider` has no intrinsic height in ImageRenderer.
                HStack(spacing: 0) {
                    ShareFigure(title: "Monthly", value: Text(plan.monthlyContribution, format: .wholeCurrency(currency)))
                    separator
                    ShareFigure(title: "Duration", value: Text("^[\(plan.years) Year](inflect: true)"))
                    separator
                    ShareFigure(title: "Return", value: Text(verbatim: plan.annualReturn.percentText(0...1)))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))

                Text("Calculated with Owlvest")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 380)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.3))
            .frame(width: 1, height: 34)
    }
}

private struct ShareFigure: View {
    let title: LocalizedStringKey
    let value: Text

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize()
            value
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Wraps a rendered image so it can drive `.sheet(item:)`.
struct RenderedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Preview of the share image with a share button.
struct ShareImageSheet: View {
    let rendered: RenderedImage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let image = Image(uiImage: rendered.image)
        NavigationStack {
            ScrollView {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                    .padding(24)
                    .accessibilityLabel("Share image preview")
            }
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: image, preview: SharePreview(String(localized: "My ETF Savings Plan"), image: image)) {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .navigationTitle("Share as Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

extension ShareCard {
    /// Renders the card at 3× scale (1140 px wide).
    @MainActor
    func render(currency: String, palette: Palette?) -> RenderedImage? {
        let renderer = ImageRenderer(content: self
            .environment(\.currencyCode, currency)
            .environment(\.paletteOverride, palette))
        renderer.scale = 3
        return renderer.uiImage.map { RenderedImage(image: $0) }
    }
}
