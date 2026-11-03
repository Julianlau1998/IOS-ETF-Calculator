//
//  AdsManager.swift
//  ETF Calculator
//

import AppTrackingTransparency
import GoogleMobileAds
import Observation
import SwiftUI
import UIKit
import UserMessagingPlatform

/// Gathers consent (UMP), starts AdMob and decides when ads may appear.
///
/// Formats, from most to least frequent:
/// - Native ads styled like the app's list cards (one per screen).
/// - Interstitials at natural breaks: after saving/sharing, leaving a detail
///   screen or switching tabs — capped by count and a cooldown.
/// - An app open ad when returning after a longer break.
/// - Opt-in rewarded ads that unlock Premium features for an hour (3× a day).
/// Never while someone is typing, never for subscribers.
@Observable
@MainActor
final class AdsManager: NSObject {
    #if DEBUG
    // Google's official test units so development never serves live ads.
    static let nativeUnitID = "ca-app-pub-3940256099942544/3986624511"
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    static let appOpenUnitID = "ca-app-pub-3940256099942544/5575463023"
    static let rewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    static let nativeUnitID = "ca-app-pub-1006221991146598/9854827686"
    static let interstitialUnitID = "ca-app-pub-1006221991146598/6195857894"
    static let appOpenUnitID = "ca-app-pub-1006221991146598/6521912321"
    static let rewardedUnitID = "ca-app-pub-1006221991146598/7240931774"
    #endif

    /// Number of completed actions between two interstitials.
    private let actionsPerInterstitial = 3
    /// Minimum time between two full-screen ads (interstitial or app open).
    private let interstitialCooldown: TimeInterval = 3 * 60
    /// Tab switches count as a fraction of an action (every n-th switch counts).
    private let tabSwitchesPerAction = 3
    /// Minimum time in the background before an app open ad may appear.
    private let appOpenMinimumBackgroundTime: TimeInterval = 30 * 60
    /// Minimum time between two app open ads.
    private let appOpenCooldown: TimeInterval = 4 * 60 * 60
    /// One native ad per placement: calculator, goal, scenarios, portfolio, year table.
    private let nativeAdCount = 5
    /// Native ads are refreshed at most this often when the app becomes active.
    private let nativeRefreshInterval: TimeInterval = 10 * 60

    private(set) var canRequestAds = false
    private(set) var isPrivacyOptionsRequired = false
    /// Loaded native ads; each placement shows the ad at its slot index.
    private(set) var nativeAds: [NativeAd] = []

    private var hasStarted = false
    private var interstitial: InterstitialAd?
    private var completedActions = 0
    private var lastInterstitial = Date.now
    private var nativeLoader: AdLoader?
    private var pendingNativeAds: [NativeAd] = []
    private var lastNativeLoad = Date.distantPast
    private var tabSwitches = 0
    private var appOpenAd: AppOpenAd?
    private var lastAppOpenAd = Date.now
    private var enteredBackgroundAt: Date?
    private var rewardedAd: RewardedAd?
    /// Whether an opt-in rewarded ad is ready to be offered.
    private(set) var isRewardedAdReady = false

    /// Requests consent information and, once allowed, starts the SDK.
    /// Subscribers never see ads, so nothing is loaded for them.
    func start(isPremium: Bool) async {
        // Subscribers never see ads, so there's nothing to ask consent for.
        guard !hasStarted, !isPremium else { return }
        hasStarted = true

        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            if let root = UIApplication.shared.topViewController {
                try await ConsentForm.loadAndPresentIfRequired(from: root)
            }
        } catch {
            print("Consent gathering failed: \(error.localizedDescription)")
        }
        // Ask for tracking after Google's consent form, so personalized ads are possible.
        // If the UMP IDFA message is set up in AdMob it has asked already, and this returns at once.
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        refreshConsentState()

        guard canRequestAds else { return }
        #if DEBUG
        // Test ads must never play sound during development (Simulator audio
        // follows the Mac's output, which may be AirPlay speakers).
        MobileAds.shared.isApplicationMuted = true
        MobileAds.shared.applicationVolume = 0
        #endif
        await MobileAds.shared.start()
        loadNativeAds()
        await loadInterstitial()
        await loadAppOpenAd()
        await loadRewardedAd()
    }

    /// Shows Google's privacy options form so people can change their choice.
    func presentPrivacyOptions() async {
        guard let root = UIApplication.shared.topViewController else { return }
        try? await ConsentForm.presentPrivacyOptionsForm(from: root)
        refreshConsentState()
    }

    /// Call after a meaningful, finished action. Occasionally shows an interstitial.
    func registerCompletedAction(isPremium: Bool) {
        guard canRequestAds, !isPremium else { return }
        completedActions += 1
        guard completedActions >= actionsPerInterstitial,
              Date.now.timeIntervalSince(lastFullScreenAd) >= interstitialCooldown,
              let interstitial,
              let root = UIApplication.shared.topViewController else { return }

        completedActions = 0
        lastInterstitial = .now
        interstitial.present(from: root)
        self.interstitial = nil
        Task { await loadInterstitial() }
    }

    /// Tab changes are natural breaks; every few switches count as one action.
    func registerTabSwitch(isPremium: Bool) {
        tabSwitches += 1
        guard tabSwitches >= tabSwitchesPerAction else { return }
        tabSwitches = 0
        registerCompletedAction(isPremium: isPremium)
    }

    private var lastFullScreenAd: Date { max(lastInterstitial, lastAppOpenAd) }

    // MARK: App open

    func appDidEnterBackground() {
        enteredBackgroundAt = .now
    }

    /// Shows an app open ad when returning after a longer break.
    func appDidBecomeActive(isPremium: Bool, isBlocked: Bool) {
        defer { enteredBackgroundAt = nil }
        guard canRequestAds, !isPremium, !isBlocked,
              let enteredBackgroundAt,
              Date.now.timeIntervalSince(enteredBackgroundAt) >= appOpenMinimumBackgroundTime,
              Date.now.timeIntervalSince(lastAppOpenAd) >= appOpenCooldown,
              Date.now.timeIntervalSince(lastFullScreenAd) >= interstitialCooldown,
              let appOpenAd,
              let root = UIApplication.shared.topViewController else { return }

        lastAppOpenAd = .now
        appOpenAd.present(from: root)
        self.appOpenAd = nil
        Task { await loadAppOpenAd() }
    }

    private func loadAppOpenAd() async {
        appOpenAd = try? await AppOpenAd.load(with: Self.appOpenUnitID, request: Request())
    }

    // MARK: Rewarded

    /// Shows the rewarded ad; `onReward` runs once the user earned the reward.
    func showRewardedAd(onReward: @escaping @MainActor () -> Void) {
        guard let rewardedAd, let root = UIApplication.shared.topViewController else { return }
        rewardedAd.present(from: root) {
            Task { @MainActor in onReward() }
        }
        self.rewardedAd = nil
        isRewardedAdReady = false
        lastInterstitial = .now
        Task { await loadRewardedAd() }
    }

    private func loadRewardedAd() async {
        rewardedAd = try? await RewardedAd.load(with: Self.rewardedUnitID, request: Request())
        isRewardedAdReady = rewardedAd != nil
    }

    /// Fetches fresh native ads if the current ones are old enough.
    func refreshNativeAdsIfNeeded(isPremium: Bool) {
        guard hasStarted, canRequestAds, !isPremium,
              Date.now.timeIntervalSince(lastNativeLoad) >= nativeRefreshInterval else { return }
        loadNativeAds()
    }

    private func refreshConsentState() {
        let info = ConsentInformation.shared
        canRequestAds = info.canRequestAds
        isPrivacyOptionsRequired = info.privacyOptionsRequirementStatus == .required
    }

    private func loadInterstitial() async {
        interstitial = try? await InterstitialAd.load(with: Self.interstitialUnitID, request: Request())
    }

    private func loadNativeAds() {
        guard nativeLoader?.isLoading != true else { return }
        lastNativeLoad = .now

        let multiple = MultipleAdsAdLoaderOptions()
        multiple.numberOfAds = nativeAdCount
        let media = NativeAdMediaAdLoaderOptions()
        media.mediaAspectRatio = .landscape
        let video = VideoOptions()
        // Video ads in a calculator should never surprise anyone with sound.
        video.shouldStartMuted = true

        let loader = AdLoader(
            adUnitID: Self.nativeUnitID,
            rootViewController: UIApplication.shared.topViewController,
            adTypes: [.native],
            options: [multiple, media, video]
        )
        loader.delegate = self
        pendingNativeAds = []
        nativeLoader = loader
        loader.load(Request())
    }
}

extension AdsManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        pendingNativeAds.append(nativeAd)
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: any Error) {
        print("Native ad failed to load: \(error.localizedDescription)")
    }

    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        // Swap all at once so placements don't flicker between old and new ads.
        if !pendingNativeAds.isEmpty {
            nativeAds = pendingNativeAds
        }
        pendingNativeAds = []
    }
}

extension UIApplication {
    /// The view controller currently on top, used to present ad and consent UI.
    var topViewController: UIViewController? {
        let scene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    /// Ends editing in whichever text field is currently active.
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
