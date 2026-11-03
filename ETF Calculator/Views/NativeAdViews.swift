//
//  NativeAdViews.swift
//  ETF Calculator
//

import GoogleMobileAds
import SwiftUI
import UIKit

/// A list section showing one native ad, styled like the app's own cards.
/// Each placement uses a distinct slot, because a native ad may only be
/// displayed in one view at a time.
struct NativeAdSection: View {
    let slot: Int

    @Environment(AdsManager.self) private var ads
    @Environment(StoreManager.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        if !store.isPremium, ads.nativeAds.indices.contains(slot) {
            Section {
                NativeAdCard(ad: ads.nativeAds[slot])
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
            } footer: {
                HStack {
                    Spacer()
                    Button("Remove Ads") {
                        router.isShowingPaywall = true
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }
}

/// A single native ad row for use inside an existing list section.
struct NativeAdRow: View {
    let slot: Int

    @Environment(AdsManager.self) private var ads
    @Environment(StoreManager.self) private var store

    var body: some View {
        if !store.isPremium, ads.nativeAds.indices.contains(slot) {
            NativeAdCard(ad: ads.nativeAds[slot])
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        }
    }
}

/// Bridges the UIKit `NativeAdView` (required by AdMob for click and
/// impression tracking) into SwiftUI.
struct NativeAdCard: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> NativeAdCardView {
        NativeAdCardView()
    }

    func updateUIView(_ view: NativeAdCardView, context: Context) {
        view.configure(with: ad)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeAdCardView, context: Context) -> CGSize? {
        let width = proposal.width ?? 360
        let size = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: ceil(size.height))
    }
}

/// Programmatic native ad layout:
///
///     [icon]  Headline                       (i)
///             [Ad] Advertiser
///     Body text …
///     ┌──────────── media 16:9 ────────────┐
///     └────────────────────────────────────┘
///     (          Call to action            )
final class NativeAdCardView: NativeAdView {
    private let iconImageView = UIImageView()
    private let headlineLabel = UILabel()
    private let badgeLabel = InsetLabel()
    private let advertiserLabel = UILabel()
    private let bodyLabel = UILabel()
    private let adMediaView = MediaView()
    private let callToActionButton = UIButton(configuration: .filled())
    private var mediaAspectConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        setUpViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with ad: NativeAd) {
        guard nativeAd !== ad else { return }

        headlineLabel.text = ad.headline
        advertiserLabel.text = ad.advertiser ?? ad.store
        advertiserLabel.isHidden = advertiserLabel.text?.isEmpty ?? true
        bodyLabel.text = ad.body
        bodyLabel.isHidden = ad.body?.isEmpty ?? true
        iconImageView.image = ad.icon?.image
        iconImageView.isHidden = ad.icon == nil

        let aspectRatio = ad.mediaContent.aspectRatio
        adMediaView.isHidden = aspectRatio <= 0
        mediaAspectConstraint?.isActive = false
        mediaAspectConstraint = adMediaView.heightAnchor.constraint(
            equalTo: adMediaView.widthAnchor,
            multiplier: aspectRatio > 0 ? min(1, 1 / aspectRatio) : 9.0 / 16.0
        )
        mediaAspectConstraint?.priority = .defaultHigh
        mediaAspectConstraint?.isActive = true
        adMediaView.mediaContent = ad.mediaContent

        callToActionButton.configuration?.title = ad.callToAction
        callToActionButton.isHidden = ad.callToAction == nil

        // Assigning the ad last registers all asset views with the SDK.
        nativeAd = ad
    }

    private func setUpViews() {
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.layer.cornerRadius = 10
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.clipsToBounds = true
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 44),
            iconImageView.heightAnchor.constraint(equalToConstant: 44)
        ])

        headlineLabel.font = .preferredFont(forTextStyle: .headline)
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.numberOfLines = 2

        badgeLabel.text = String(localized: "Ad")
        badgeLabel.font = .preferredFont(forTextStyle: .caption2).bold()
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.textColor = .secondaryLabel
        badgeLabel.backgroundColor = .tertiarySystemFill
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        advertiserLabel.font = .preferredFont(forTextStyle: .footnote)
        advertiserLabel.adjustsFontForContentSizeCategory = true
        advertiserLabel.textColor = .secondaryLabel

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 3

        adMediaView.layer.cornerRadius = 12
        adMediaView.layer.cornerCurve = .continuous
        adMediaView.clipsToBounds = true
        adMediaView.contentMode = .scaleAspectFill

        callToActionButton.configuration?.cornerStyle = .capsule
        callToActionButton.configuration?.buttonSize = .large
        // The SDK handles taps on the whole ad view; the button must not swallow them.
        callToActionButton.isUserInteractionEnabled = false

        let meta = UIStackView(arrangedSubviews: [badgeLabel, advertiserLabel])
        meta.spacing = 6
        meta.alignment = .center

        let titles = UIStackView(arrangedSubviews: [headlineLabel, meta])
        titles.axis = .vertical
        titles.spacing = 3
        titles.alignment = .leading

        let header = UIStackView(arrangedSubviews: [iconImageView, titles])
        header.spacing = 12
        header.alignment = .center
        // Leave room for the AdChoices icon the SDK places in the top-right corner.
        header.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 24)
        header.isLayoutMarginsRelativeArrangement = true

        let content = UIStackView(arrangedSubviews: [header, bodyLabel, adMediaView, callToActionButton])
        content.axis = .vertical
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        headlineView = headlineLabel
        advertiserView = advertiserLabel
        bodyView = bodyLabel
        iconView = iconImageView
        mediaView = adMediaView
        callToActionView = callToActionButton
    }
}

/// A label with padding, used for the "Ad" attribution badge.
private final class InsetLabel: UILabel {
    private let insets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
