//
//  ReminderService.swift
//  ETF Calculator
//

import Foundation
import UserNotifications

/// Monthly local notification reminding people to record their portfolio value.
enum ReminderService {
    static let storageKey = "portfolio.reminder"
    private static let identifier = "portfolio.monthlyReminder"

    /// Asks for permission (once) and schedules the reminder for the 1st of every month.
    /// Returns `false` if notifications aren't allowed.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "How's Your Portfolio Doing?")
        content.body = String(localized: "Record your current portfolio value and see whether you're on track.")
        content.sound = .default

        var date = DateComponents()
        date.day = 1
        date.hour = 18
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
