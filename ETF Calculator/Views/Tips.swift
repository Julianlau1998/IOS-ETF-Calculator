//
//  Tips.swift
//  ETF Calculator
//

import SwiftUI
import TipKit

/// Tips appear once and disappear after the action is used.
enum AppTips {
    /// Donated on every launch; some tips wait for a second session.
    static let appOpened = Tips.Event(id: "appOpened")

    /// False while a full-screen sheet (welcome, Premium, settings) covers the app,
    /// so tips anchored to views behind it don't pop up on top of the sheet.
    @Parameter static var isAppVisible: Bool = false

    static func configure() {
        #if DEBUG
        // Clean UI for App Store screenshots.
        if ProcessInfo.processInfo.arguments.contains("-hideTips") {
            Tips.hideAllTipsForTesting()
        }
        #endif
        try? Tips.configure([.displayFrequency(.daily)])
        Task { await appOpened.donate() }
    }
}

struct ChartScrubTip: Tip {
    var title: Text { Text("Explore Your Growth") }
    var message: Text? { Text("Drag across the chart to see your portfolio in any year.") }
    var image: Image? { Image(systemName: "hand.draw") }

    var rules: [Rule] {
        #Rule(AppTips.$isAppVisible) { $0 == true }
    }
}

struct ShareImageTip: Tip {
    var title: Text { Text("Share Your Plan") }
    var message: Text? { Text("Turn your plan into a beautiful image for messages or social media.") }
    var image: Image? { Image(systemName: "photo") }

    var rules: [Rule] {
        #Rule(AppTips.$isAppVisible) { $0 == true }
        #Rule(AppTips.appOpened) { $0.donations.count >= 2 }
    }
}

struct BrokerImportTip: Tip {
    var title: Text { Text("Import from Your Broker") }
    var message: Text? { Text("Export a CSV in your broker's app and share it with Owlvest — your positions are added automatically.") }
    var image: Image? { Image(systemName: "square.and.arrow.down") }

    var rules: [Rule] {
        #Rule(AppTips.$isAppVisible) { $0 == true }
    }
}
