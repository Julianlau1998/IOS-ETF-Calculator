//
//  ETFCalculatorApp.swift
//  ETF Calculator
//

import SwiftData
import SwiftUI

@main
struct ETFCalculatorApp: App {
    @State private var calculator = CalculatorModel()
    @State private var router = AppRouter()
    @State private var store = StoreManager()
    @State private var ads = AdsManager()
    @State private var taxStore = TaxStore()
    private let container = DataStore.makeContainer()

    init() {
        AppTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(calculator)
                .environment(router)
                .environment(store)
                .environment(ads)
                .environment(taxStore)
        }
        .modelContainer(container)
    }
}
