import BarrierCore
import Foundation
import UIKit
import UserNotifications

/// Local notifications: planned on the phone, no server. Done / In 30 min /
/// Not tonight work straight from the Lock Screen.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    static let routineCategory = "routine"
    static let doneAction = "done"
    static let snoozeAction = "snooze"
    static let skipAction = "skip"
    static let timerID = "timer"

    private var center: UNUserNotificationCenter { .current() }

    func configure() {
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "In 30 minutes", options: [], icon: UNNotificationActionIcon(systemImageName: "clock"))
        let skip = UNNotificationAction(identifier: Self.skipAction, title: "Not tonight", options: [], icon: UNNotificationActionIcon(systemImageName: "moon.zzz"))
        let routine = UNNotificationCategory(identifier: Self.routineCategory, actions: [done, snooze, skip], intentIdentifiers: [], options: [])
        center.setNotificationCategories([routine])
    }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Scheduling

    func reschedule(_ state: AppState) async {
        let status = await status()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let planned = Reminders.plan(state)
        let pending = await center.pendingNotificationRequests()
        // Keep one-off timers and snoozes; replace everything planned.
        let replace = pending.map(\.identifier).filter { $0 != Self.timerID && !$0.hasPrefix("snooze:") }
        center.removePendingNotificationRequests(withIdentifiers: replace)
        let cal = Calendar.current
        for r in planned {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.threadIdentifier = r.slot?.rawValue ?? r.kind.rawValue
            content.interruptionLevel = r.kind == .keepAlive ? .passive : .active
            content.relevanceScore = r.kind == .main ? 1 : 0.5
            if r.actionable { content.categoryIdentifier = Self.routineCategory }
            var info: [String: Any] = ["link": r.link, "kind": r.kind.rawValue]
            if let s = r.slot { info["slot"] = s.rawValue }
            if let d = r.day { info["day"] = d.iso }
            content.userInfo = info
            let fireDate = r.fire.date(calendar: cal).addingTimeInterval(TimeInterval(r.offsetMin * 60))
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
    }

    func removeAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Clear the delivered banners for a routine once it's logged.
    func clearDelivered(day: Day, slot: Slot) {
        let ids = ["\(day.iso):\(slot.rawValue):main", "\(day.iso):\(slot.rawValue):nudge", "snooze:\(day.iso):\(slot.rawValue)"]
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func scheduleTimer(at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = ["kind": "timer"]
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.timerID, content: content, trigger: trigger))
    }

    func cancelTimer() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.timerID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.timerID])
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Reminders are on"
        content.body = "This is how Barrier will tap you on the shoulder. Long-press a reminder for Done and Not tonight."
        content.sound = .default
        content.categoryIdentifier = Self.routineCategory
        content.userInfo = ["kind": "test", "link": "today"]
        center.add(UNNotificationRequest(identifier: "test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }

    private func snooze(_ content: UNNotificationContent, day: String, slot: String) {
        let c = (content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        c.title = content.title
        c.body = content.body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
        center.add(UNNotificationRequest(identifier: "snooze:\(day):\(slot)", content: c, trigger: trigger))
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let slotRaw = info["slot"] as? String
        let dayRaw = info["day"] as? String
        let link = info["link"] as? String
        switch response.actionIdentifier {
        case Self.doneAction:
            guard let slot = slotRaw.flatMap(Slot.init(rawValue:)), let day = dayRaw.flatMap(Day.init(iso:)) else { return }
            await MainActor.run {
                let model = AppModel.shared
                model.refreshClock()
                model.update { $0.markDone(slot, on: day, today: model.today) }
                model.saveNow()
                self.clearDelivered(day: day, slot: slot)
            }
        case Self.skipAction:
            guard let slot = slotRaw.flatMap(Slot.init(rawValue:)), let day = dayRaw.flatMap(Day.init(iso:)) else { return }
            await MainActor.run {
                let model = AppModel.shared
                model.refreshClock()
                if model.state.entry(day, slot) == nil {
                    model.update { $0.markSkipped(slot, on: day, today: model.today) }
                    model.saveNow()
                }
                self.clearDelivered(day: day, slot: slot)
            }
        case Self.snoozeAction:
            if let d = dayRaw, let s = slotRaw {
                snooze(response.notification.request.content, day: d, slot: s)
            }
        case UNNotificationDefaultActionIdentifier:
            if let link {
                await MainActor.run { AppModel.shared.handle(link: link) }
            }
        default:
            break
        }
    }
}
