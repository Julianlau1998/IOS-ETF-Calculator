//
//  AppRouter.swift
//  ETF Calculator
//

import Foundation
import Observation

enum AppTab: Hashable {
    case calculator, goal, payout, scenarios, portfolio
}

/// App-wide navigation state shared by all tabs.
@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .calculator
    var isShowingSettings = false
    var isShowingPaywall = false
    /// Shown before anything else (including the ad consent form) on first launch / after updates.
    var isShowingWelcome = WelcomeView.needsPresentation
    /// Updated from keyboard notifications in `RootView`.
    var isKeyboardVisible = false
    /// A broker export waiting to be reviewed in the portfolio tab.
    var pendingImport: PortfolioImport?
    var importError: String?

    /// Reads a CSV shared from another app (e.g. Trade Republic) or picked in Files.
    func openPortfolioFile(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        selectedTab = .portfolio
        do {
            let data = try Data(contentsOf: url)
            pendingImport = PortfolioImport(result: try PortfolioCSVImporter.parse(data))
        } catch {
            importError = error.localizedDescription
        }
        // Files shared into the app are copied to Documents/Inbox; clean up.
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
    }
}

/// Identifiable wrapper so an import can drive a sheet.
struct PortfolioImport: Identifiable {
    let id = UUID()
    let result: PortfolioCSVImporter.Result
}
