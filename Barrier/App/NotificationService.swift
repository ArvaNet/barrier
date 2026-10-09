import BarrierCore
import Foundation
import UIKit
import UserNotifications

/// Local notifications: planned on the phone, no server. Done / In 30 min /
/// Not tonight work straight from the Lock Screen.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()

    static let routineCategory = "routine"
    static let doneAction = "done"
    static let snoozeAction = "snooze"
    static let skipAction = "skip"

    private var center: UNUserNotificationCenter { .current() }
    /// Reschedules run one at a time, so two can never interleave remove/add.
    private let gate = SerialGate()

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
        // Never plan from a blank or half-set-up state: that would wipe real reminders.
        guard state.onboarded else { return }
        await gate.run { await self.applyPlan(state) }
    }

    /// Change only what differs from what's already pending.
    private func applyPlan(_ state: AppState) async {
        let status = await status()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let cal = Calendar.barrier
        var wanted: [String: UNNotificationRequest] = [:]
        for r in Reminders.plan(state, calendar: cal) {
            wanted[r.id] = request(for: r, calendar: cal)
        }
        let pending = await center.pendingNotificationRequests()
        var stale: [String] = []
        var unchanged = Set<String>()
        for p in pending {
            // One-off timers and snoozes aren't part of the plan.
            if p.identifier.hasPrefix("timer") || p.identifier.hasPrefix("snooze:") { continue }
            if let w = wanted[p.identifier], Self.same(p, w) {
                unchanged.insert(p.identifier)
            } else {
                stale.append(p.identifier)
            }
        }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for (id, req) in wanted where !unchanged.contains(id) {
            try? await center.add(req)
        }
    }

    private func request(for r: PlannedReminder, calendar cal: Calendar) -> UNNotificationRequest {
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
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        // Without this, iOS reads the numbers in the phone's own calendar
        // (Buddhist, Hebrew…) and the reminder never fires.
        comps.calendar = cal
        comps.timeZone = cal.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: r.id, content: content, trigger: trigger)
    }

    private static func same(_ a: UNNotificationRequest, _ b: UNNotificationRequest) -> Bool {
        guard a.content.title == b.content.title,
              a.content.body == b.content.body,
              a.content.categoryIdentifier == b.content.categoryIdentifier,
              let ta = a.trigger as? UNCalendarNotificationTrigger,
              let tb = b.trigger as? UNCalendarNotificationTrigger,
              let da = ta.nextTriggerDate(), let db = tb.nextTriggerDate() else { return false }
        return abs(da.timeIntervalSince(db)) < 1
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

    // MARK: Wait timers (one per routine)

    static func timerID(_ ritualID: String) -> String { "timer:\(ritualID)" }

    func scheduleTimer(at date: Date, title: String, body: String, ritualID: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = ["kind": "timer"]
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.timerID(ritualID), content: content, trigger: trigger))
    }

    func cancelTimer(ritualID: String) {
        let id = Self.timerID(ritualID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
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
        case Self.doneAction, Self.skipAction:
            guard let slot = slotRaw.flatMap(Slot.init(rawValue:)), let day = dayRaw.flatMap(Day.init(iso:)) else { return }
            let done = response.actionIdentifier == Self.doneAction
            let state: AppState? = await MainActor.run {
                let model = AppModel.shared
                model.refreshClock()
                model.retryLoadIfNeeded()
                guard !model.loadFailed else {
                    // Data can't be read yet (e.g. before first unlock): keep the tap
                    // in the inbox so it's applied once the app can load.
                    SharedStore.appendInbox(InboxItem(day: day, slot: slot, action: done ? .done : .skip))
                    return nil
                }
                if done {
                    model.update { $0.markDone(slot, on: day, today: model.today) }
                } else if model.state.entry(day, slot) == nil {
                    model.update { $0.markSkipped(slot, on: day, today: model.today) }
                }
                model.saveNow()
                model.endRitual(slot, day)
                return model.state
            }
            clearDelivered(day: day, slot: slot)
            // Re-plan now: iOS may suspend the app as soon as this returns.
            if let state { await reschedule(state) }
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

/// Runs async jobs strictly one after another.
actor SerialGate {
    private var tail: Task<Void, Never>?

    func run(_ op: @escaping @Sendable () async -> Void) async {
        let previous = tail
        let task = Task {
            await previous?.value
            await op()
        }
        tail = task
        await task.value
    }
}
