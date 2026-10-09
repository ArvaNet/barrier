import Foundation

// Plans the local notifications. iOS keeps at most 64 pending, so the plan is
// bounded: main reminders for 14 days, nudges for the next 3, sunscreen for 7.
// Nights more than 3 days out get generic text, because the exact night can
// shift if one is skipped and nobody opens the app.

public enum ReminderKind: String, Sendable, Codable {
    case main, nudge, spf, followUp, keepAlive, timer
}

public struct PlannedReminder: Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: ReminderKind
    public var slot: Slot?
    public var day: Day?
    public var fire: DayTime
    /// Extra minutes after `fire` (nudges).
    public var offsetMin: Int
    public var title: String
    public var body: String
    /// Deep link path, e.g. "ritual/pm/2026-10-09".
    public var link: String
    /// Whether to show Done / Snooze / Not tonight actions.
    public var actionable: Bool
}

public enum Reminders {
    public static let horizonDays = 14
    public static let specificDays = 3
    public static let nudgeDays = 3
    public static let spfDays = 7

    public static func mainCopy(_ inst: Instance, photoNight: Bool) -> (title: String, body: String) {
        if inst.rest == .pause {
            return inst.slot == .pm
                ? ("Simple night", "Plan paused. Just cleanse and moisturize.")
                : ("Simple morning", "Plan paused. Keep the basics going.")
        }
        let names = stepNames(inst)
        if inst.slot == .pm {
            let title = "Tonight: \(inst.label)" + (photoNight ? " · photo night" : "")
            if inst.hasActives, let a = inst.steps.first(where: \.active) {
                let line = a.step.amount.map { "\(a.product.name): \($0.lowercased())" } ?? a.product.name
                return (title, "\(line). Tap to start.")
            }
            return (title, "\(names.isEmpty ? "Cleanse and moisturize" : names). No actives tonight.")
        }
        let title = inst.label == "Morning routine" ? "Morning routine" : "This morning: \(inst.label)"
        return (title, names.isEmpty ? "Open Barrier for your steps." : names)
    }

    public static func nudgeCopy(_ inst: Instance) -> (title: String, body: String) {
        if inst.slot == .am {
            return ("Morning routine still open", "Two minutes now covers the whole day. Sunscreen last.")
        }
        let n = inst.steps.count
        let wait = inst.totalWait
        let time = wait > 0 ? ", about \(wait + n * 2) min" : ""
        if inst.hasActives {
            return ("Still on for \(inst.label.lowercased())?", "\(n) steps\(time). Not happening tonight? Long-press and tap Not tonight.")
        }
        return ("Quick one tonight", "Recovery night: cleanse, moisturize, sleep.")
    }

    static func generic(_ slot: Slot) -> (String, String) {
        slot == .pm
            ? ("Evening routine", "Open Barrier to see tonight’s steps.")
            : ("Morning routine", "Open Barrier to see this morning’s steps.")
    }

    static func stepNames(_ inst: Instance, max: Int = 4) -> String {
        let names = inst.steps.map(\.product.name)
        guard !names.isEmpty else { return "" }
        let shown = names.prefix(max).joined(separator: " → ")
        return names.count > max ? "\(shown) +\(names.count - max)" : shown
    }

    /// Everything to schedule, given the state and the current moment.
    public static func plan(_ state: AppState, now: Date = Date(), calendar: Calendar = .barrier) -> [PlannedReminder] {
        guard state.onboarded, state.settings.remindersOn else { return [] }
        let today = Day.routineDay(now, calendar: calendar)
        let end = today.adding(horizonDays - 1)
        let settings = state.settings
        var out: [PlannedReminder] = []

        for slot in [Slot.am, .pm] {
            let sp = state.plan[slot]
            guard sp.enabled, !sp.steps.isEmpty else { continue }
            // Once a night with actives is still open, later nights could shift
            // (Barrier never skips ahead), so their reminders stay generic.
            var uncertain = false
            for inst in Engine.timeline(state, slot: slot, from: today, to: end, today: today) {
                defer { if inst.hasActives && !inst.isResolved { uncertain = true } }
                if inst.isResolved || inst.status == .off || inst.steps.isEmpty { continue }
                let fire = DayTime(inst.day, sp.time)
                let fireDate = fire.date(calendar: calendar)
                let ahead = today.days(to: inst.day)
                let link = "ritual/\(slot.rawValue)/\(inst.day.iso)"
                let photoNight = slot == .pm && settings.photoDay >= 0 && inst.day.weekday == settings.photoDay
                if fireDate > now {
                    let c = ahead < specificDays && !uncertain ? mainCopy(inst, photoNight: photoNight) : generic(slot)
                    out.append(PlannedReminder(
                        id: "\(inst.day.iso):\(slot.rawValue):main", kind: .main, slot: slot, day: inst.day, fire: fire,
                        offsetMin: 0, title: c.0, body: c.1, link: link, actionable: true
                    ))
                }
                if settings.nudge && inst.rest != .pause && ahead < nudgeDays && !uncertain {
                    let nudgeDate = fireDate.addingTimeInterval(TimeInterval(settings.nudgeAfterMin * 60))
                    if nudgeDate > now {
                        let c = nudgeCopy(inst)
                        out.append(PlannedReminder(
                            id: "\(inst.day.iso):\(slot.rawValue):nudge", kind: .nudge, slot: slot, day: inst.day, fire: fire,
                            offsetMin: settings.nudgeAfterMin, title: c.0, body: c.1, link: link, actionable: true
                        ))
                    }
                }
            }
        }

        // Midday sunscreen top-up, only when the morning includes sunscreen.
        let hasSpf = state.plan.am.enabled && state.plan.am.steps.contains { state.product($0.productId)?.kind == .spf }
        if settings.spfMidday && hasSpf {
            for i in 0..<spfDays {
                let d = today.adding(i)
                let fire = DayTime(d, settings.spfTime)
                guard fire.date(calendar: calendar) > now else { continue }
                out.append(PlannedReminder(
                    id: "\(d.iso):spf", kind: .spf, slot: nil, day: d, fire: fire, offsetMin: 0,
                    title: "Sunscreen top-up", body: "Outside today? Reapply about every 2 hours, and after sweating or swimming.",
                    link: "today", actionable: false
                ))
            }
        }

        // Dermatologist follow-up: the evening before.
        if let fu = state.plan.followUp {
            let fire = DayTime(fu.day.adding(-1), ClockTime(18, 0))
            let open = state.questions.filter { !$0.answered }.count
            if fire.date(calendar: calendar) > now {
                let who = (fu.with?.isEmpty == false ? fu.with! : "Dermatologist")
                out.append(PlannedReminder(
                    id: "\(fu.day.iso):followup", kind: .followUp, slot: nil, day: fu.day, fire: fire, offsetMin: 0,
                    title: "\(who) tomorrow",
                    body: open > 0 ? "Your report is ready, with \(open) question\(open == 1 ? "" : "s") to ask." : "Your report is ready to show. Add any questions tonight.",
                    link: "report", actionable: false
                ))
            }
        }

        // If the app isn't opened for ~two weeks, the reminders would quietly run out.
        let lastDay = today.adding(horizonDays - 2)
        let keep = DayTime(lastDay, ClockTime(12, 0))
        if keep.date(calendar: calendar) > now {
            out.append(PlannedReminder(
                id: "keepalive", kind: .keepAlive, slot: nil, day: lastDay, fire: keep, offsetMin: 0,
                title: "Keep your reminders coming",
                body: "Open Barrier once to plan the next two weeks.", link: "today", actionable: false
            ))
        }

        let sorted = out.sorted { a, b in
            let da = a.fire.date(calendar: calendar).addingTimeInterval(TimeInterval(a.offsetMin * 60))
            let db = b.fire.date(calendar: calendar).addingTimeInterval(TimeInterval(b.offsetMin * 60))
            return da < db
        }
        return Array(sorted.prefix(60))
    }
}
