//
//  TaxStore.swift
//  ETF Calculator
//

import Foundation
import Observation

/// Persists the tax assumptions edited in Settings.
@Observable
@MainActor
final class TaxStore {
    typealias Key = TaxSettings.Key

    var settings: TaxSettings {
        didSet { save() }
    }

    /// Whether the Basiszins is fetched automatically.
    var isBaseRateAutomatic: Bool {
        didSet { UserDefaults.standard.set(isBaseRateAutomatic, forKey: Key.baseRateAutomatic) }
    }

    /// Year of the automatically fetched Basiszins, if any.
    private(set) var baseRateYear: Int?

    init() {
        let defaults = UserDefaults.standard
        var settings = TaxSettings()
        if let raw = defaults.string(forKey: Key.region), let region = TaxRegion(rawValue: raw) { settings.region = region }
        settings.isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? settings.isEnabled
        settings.rate = defaults.object(forKey: Key.rate) as? Double ?? settings.rate
        settings.partialExemption = defaults.object(forKey: Key.partialExemption) as? Double ?? settings.partialExemption
        settings.allowance = defaults.object(forKey: Key.allowance) as? Double ?? settings.allowance
        settings.includesAdvanceLumpSum = defaults.object(forKey: Key.includesAdvanceLumpSum) as? Bool ?? settings.includesAdvanceLumpSum
        settings.baseRate = defaults.object(forKey: Key.baseRate) as? Double ?? settings.baseRate
        if let raw = defaults.string(forKey: Key.usAccount), let account = USAccountType(rawValue: raw) { settings.usAccount = account }
        settings.usCapitalGainsRate = defaults.object(forKey: Key.usCapitalGainsRate) as? Double ?? settings.usCapitalGainsRate
        settings.usStateRate = defaults.object(forKey: Key.usStateRate) as? Double ?? settings.usStateRate
        settings.usIncomeRate = defaults.object(forKey: Key.usIncomeRate) as? Double ?? settings.usIncomeRate
        settings.internationalRate = defaults.object(forKey: Key.internationalRate) as? Double ?? settings.internationalRate
        settings.internationalAllowance = defaults.object(forKey: Key.internationalAllowance) as? Double ?? settings.internationalAllowance
        self.settings = settings
        isBaseRateAutomatic = defaults.object(forKey: Key.baseRateAutomatic) as? Bool ?? true
        baseRateYear = defaults.object(forKey: Key.baseRateYear) as? Int
    }

    /// Fetches the latest Basiszins (if automatic) and applies it.
    func refreshBaseRate() async {
        await BaseRateService.refreshIfNeeded()
        guard isBaseRateAutomatic else { return }
        let defaults = UserDefaults.standard
        if let rate = defaults.object(forKey: Key.baseRate) as? Double, rate != settings.baseRate {
            settings.baseRate = rate
        }
        baseRateYear = defaults.object(forKey: Key.baseRateYear) as? Int
    }

    func resetToRegionDefaults() {
        let defaults = TaxSettings()
        let region = settings.region
        switch region {
        case .germany:
            settings.rate = defaults.rate
            settings.partialExemption = defaults.partialExemption
            settings.allowance = defaults.allowance
            settings.includesAdvanceLumpSum = defaults.includesAdvanceLumpSum
        case .unitedStates:
            settings.usAccount = defaults.usAccount
            settings.usCapitalGainsRate = defaults.usCapitalGainsRate
            settings.usStateRate = defaults.usStateRate
            settings.usIncomeRate = defaults.usIncomeRate
        case .international:
            settings.internationalRate = defaults.internationalRate
            settings.internationalAllowance = defaults.internationalAllowance
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(settings.region.rawValue, forKey: Key.region)
        defaults.set(settings.isEnabled, forKey: Key.isEnabled)
        defaults.set(settings.rate, forKey: Key.rate)
        defaults.set(settings.partialExemption, forKey: Key.partialExemption)
        defaults.set(settings.allowance, forKey: Key.allowance)
        defaults.set(settings.includesAdvanceLumpSum, forKey: Key.includesAdvanceLumpSum)
        defaults.set(settings.baseRate, forKey: Key.baseRate)
        defaults.set(settings.usAccount.rawValue, forKey: Key.usAccount)
        defaults.set(settings.usCapitalGainsRate, forKey: Key.usCapitalGainsRate)
        defaults.set(settings.usStateRate, forKey: Key.usStateRate)
        defaults.set(settings.usIncomeRate, forKey: Key.usIncomeRate)
        defaults.set(settings.internationalRate, forKey: Key.internationalRate)
        defaults.set(settings.internationalAllowance, forKey: Key.internationalAllowance)
    }
}
