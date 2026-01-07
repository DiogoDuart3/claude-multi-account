import Foundation
import UserNotifications

@MainActor
class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {
        requestAuthorization()
    }
    
    // MARK: - Authorization
    
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
            if granted {
                print("Notification authorization granted")
            }
        }
    }
    
    // MARK: - Limit Hit Notifications
    
    func notifySessionLimitHit(accountName: String, resetTime: Date?) {
        let content = UNMutableNotificationContent()
        content.title = "Session Limit Reached"
        content.subtitle = accountName
        
        if let resetTime = resetTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: resetTime, relativeTo: Date())
            content.body = "Your session limit has been reached. Resets \(relative)."
        } else {
            content.body = "Your session limit has been reached."
        }
        
        content.sound = .default
        content.categoryIdentifier = "LIMIT_HIT"
        
        scheduleNotification(content: content, identifier: "session-limit-\(accountName)")
    }
    
    func notifyWeeklyLimitHit(accountName: String, resetTime: Date?) {
        let content = UNMutableNotificationContent()
        content.title = "Weekly Limit Reached"
        content.subtitle = accountName
        
        if let resetTime = resetTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: resetTime, relativeTo: Date())
            content.body = "Your weekly limit has been reached. Resets \(relative)."
        } else {
            content.body = "Your weekly limit has been reached."
        }
        
        content.sound = .default
        content.categoryIdentifier = "LIMIT_HIT"
        
        scheduleNotification(content: content, identifier: "weekly-limit-\(accountName)")
    }
    
    // MARK: - Limit Reset Notifications
    
    func notifySessionLimitReset(accountName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Session Limit Reset"
        content.subtitle = accountName
        content.body = "Your session limit has been reset. You can continue using Claude Code."
        content.sound = .default
        content.categoryIdentifier = "LIMIT_RESET"
        
        scheduleNotification(content: content, identifier: "session-reset-\(accountName)")
    }
    
    func notifyWeeklyLimitReset(accountName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Weekly Limit Reset"
        content.subtitle = accountName
        content.body = "Your weekly limit has been reset. You can continue using Claude Code."
        content.sound = .default
        content.categoryIdentifier = "LIMIT_RESET"
        
        scheduleNotification(content: content, identifier: "weekly-reset-\(accountName)")
    }
    
    // MARK: - Schedule Reset Notifications
    
    func scheduleSessionResetNotification(accountName: String, resetTime: Date) {
        // Only schedule if reset is in the future
        guard resetTime > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Session Limit Reset"
        content.subtitle = accountName
        content.body = "Your session limit has been reset. You can continue using Claude Code."
        content.sound = .default
        content.categoryIdentifier = "LIMIT_RESET"
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: resetTime),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "scheduled-session-reset-\(accountName)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule session reset notification: \(error)")
            } else {
                print("Scheduled session reset notification for \(resetTime)")
            }
        }
    }
    
    func scheduleWeeklyResetNotification(accountName: String, resetTime: Date) {
        // Only schedule if reset is in the future
        guard resetTime > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Weekly Limit Reset"
        content.subtitle = accountName
        content.body = "Your weekly limit has been reset. You can continue using Claude Code."
        content.sound = .default
        content.categoryIdentifier = "LIMIT_RESET"
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: resetTime),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "scheduled-weekly-reset-\(accountName)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule weekly reset notification: \(error)")
            } else {
                print("Scheduled weekly reset notification for \(resetTime)")
            }
        }
    }
    
    // MARK: - Cancel Scheduled Notifications
    
    func cancelScheduledNotifications(for accountName: String) {
        let identifiers = [
            "scheduled-session-reset-\(accountName)",
            "scheduled-weekly-reset-\(accountName)"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    // MARK: - Private Helpers
    
    private func scheduleNotification(content: UNMutableNotificationContent, identifier: String) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
}
