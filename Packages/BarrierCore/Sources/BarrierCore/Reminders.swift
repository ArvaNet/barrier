import Foundation

// Plans the local notifications. iOS keeps at most 64 pending, so the plan is
// bounded: main reminders for 14 days, nudges for the next 3, sunscreen for 7.
// Nights more than 3 days out get generic text, because the exact night can
// shift if one is skipped and nobody opens the app.

public enum ReminderKind: String, Sendable, Codable {
    case main, nudge, spf, followUp, keepAlive, timer, procedure

    /// One-offs that must never be crowded out by routine reminders.
    var isOneOff: Bool { self == .followUp || self == .procedure || self == .keepAlive }
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

    /// "After shower: back" / "Back".
    static func bodyTitle(_ sp: SlotPlan) -> String {
        if let cue = sp.cue, !cue.isEmpty { return "\(cue): \(sp.displayName.lowercased())" }
        return sp.displayName
    }

    public static func bodyCopy(_ inst: Instance, sp: SlotPlan, breakFor: Procedure? = nil) -> (title: String, body: String) {
        if inst.rest == .pause {
            if let p = breakFor { return (bodyTitle(sp), "Actives break (\(p.name)). Just the basics today.") }
            return (bodyTitle(sp), "Plan paused. Just the basics today.")
        }
        if let a = inst.steps.first(where: \.active) {
            let line = a.step.amount.map { "\(a.product.name): \($0.lowercased())" } ?? a.product.name
            let more = inst.steps.count > 1 ? " +\(inst.steps.count - 1) more" : ""
            return (bodyTitle(sp), "\(line)\(more). Tap Done when it’s on.")
        }
        return (bodyTitle(sp), "\(stepNames(inst)). Tap Done when it’s on.")
    }

    public static func mainCopy(_ inst: Instance, photoNight: Bool, breakFor: Procedure? = nil) -> (title: String, body: String) {
        if inst.rest == .pause, let p = breakFor {
            let names = stepNames(inst)
            let line = "Actives break (\(p.name))" + (names.isEmpty ? ". Just the basics." : ": \(names).")
            return (inst.slot == .pm ? "Simple night" : "Simple morning", line)
        }
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

    public static func nudgeCopy(_ inst: Instance, sp: SlotPlan? = nil) -> (title: String, body: String) {
        if inst.slot == .body {
            let name = (sp?.displayName ?? "Body").lowercased()
            return ("Still to do: \(name)", "One minute and it’s logged. Long-press for Done or Skip today.")
        }
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

    static func generic(_ slot: Slot, sp: SlotPlan? = nil) -> (String, String) {
        switch slot {
        case .pm: return ("Evening routine", "Open Barrier to see tonight’s steps.")
        case .am: return ("Morning routine", "Open Barrier to see this morning’s steps.")
        case .body: return (sp.map(bodyTitle) ?? "Body routine", "Open Barrier to see today’s steps.")
        }
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

        for slot in Slot.allCases {
            let sp = state.plan[slot]
            guard sp.enabled, !sp.steps.isEmpty else { continue }
            // Once a rotating night with actives is still open, later nights could shift
            // (Barrier never skips ahead), so their reminders stay generic.
            var uncertain = false
            for inst in Engine.timeline(state, slot: slot, from: today, to: end, today: today) {
                defer { if inst.hasActives && !inst.isResolved && inst.cycleLen > 1 { uncertain = true } }
                if inst.isResolved || inst.status == .off || inst.steps.isEmpty { continue }
                let fire = DayTime(inst.day, sp.time)
                let fireDate = fire.date(calendar: calendar)
                let ahead = today.days(to: inst.day)
                let link = "ritual/\(slot.rawValue)/\(inst.day.iso)"
                let photoNight = slot == .pm && settings.photoDay >= 0 && inst.day.weekday == settings.photoDay
                if fireDate > now {
                    let specific = ahead < specificDays && !uncertain
                    let brk = inst.rest == .pause ? Procedures.breakFor(state, slot: slot, on: inst.day) : nil
                    let c = slot == .body
                        ? (specific ? bodyCopy(inst, sp: sp, breakFor: brk) : generic(slot, sp: sp))
                        : (specific ? mainCopy(inst, photoNight: photoNight, breakFor: brk) : generic(slot))
                    out.append(PlannedReminder(
                        id: "\(inst.day.iso):\(slot.rawValue):main", kind: .main, slot: slot, day: inst.day, fire: fire,
                        offsetMin: 0, title: c.0, body: c.1, link: link, actionable: true
                    ))
                }
                if settings.nudge && inst.rest != .pause && ahead < nudgeDays && !uncertain {
                    let nudgeDate = fireDate.addingTimeInterval(TimeInterval(settings.nudgeAfterMin * 60))
                    if nudgeDate > now {
                        let c = nudgeCopy(inst, sp: sp)
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

        out += procedureReminders(state, today: today, now: now, calendar: calendar)

        func at(_ r: PlannedReminder) -> Date {
            r.fire.date(calendar: calendar).addingTimeInterval(TimeInterval(r.offsetMin * 60))
        }
        // 58 leaves room under iOS's 64 for a wait timer, snoozes and a test reminder.
        // One-offs (follow-up, procedures, keep-alive) always fit; routine reminders fill the rest.
        let limit = 58
        let oneOffs = out.filter { $0.kind.isOneOff }.sorted { at($0) < at($1) }.prefix(limit - 1)
        let routine = out.filter { !$0.kind.isOneOff }.sorted { at($0) < at($1) }
        let kept = Array(routine.prefix(limit - 1 - oneOffs.count))

        // If the app isn't opened for ~two weeks, the reminders would quietly run out.
        // Ask the day before the last kept routine reminder, in case the cap cut the tail.
        var lastDay = today.adding(horizonDays - 2)
        if kept.count < routine.count, let last = kept.last?.day { lastDay = min(lastDay, last.adding(-1)) }
        var result = Array(oneOffs) + kept
        let keep = DayTime(lastDay, ClockTime(12, 0))
        if keep.date(calendar: calendar) > now {
            result.append(PlannedReminder(
                id: "keepalive", kind: .keepAlive, slot: nil, day: lastDay, fire: keep, offsetMin: 0,
                title: "Keep your reminders coming",
                body: "Open Barrier once to plan the next two weeks.", link: "today", actionable: false
            ))
        }
        return result.sorted { at($0) < at($1) }
    }

    /// The evening before a procedure, and the "after" photo check-ins.
    static func procedureReminders(_ state: AppState, today: Day, now: Date, calendar: Calendar) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        let end = today.adding(horizonDays)
        for p in Procedures.upcoming(state, today: today.adding(1)) where p.day <= end {
            let fire = DayTime(p.day.adding(-1), ClockTime(18, 0))
            guard fire.date(calendar: calendar) > now else { continue }
            let hasBefore = Procedures.recentBefore(p, in: state) != nil
            out.append(PlannedReminder(
                id: "\(p.day.iso):proc:\(p.id)", kind: .procedure, slot: nil, day: p.day, fire: fire, offsetMin: 0,
                title: "\(p.name) tomorrow",
                body: hasBefore ? "Your before photo is ready. Follow your clinic’s instructions for tomorrow."
                    : "If you can, take a before photo in good light. Follow your clinic’s instructions for tomorrow.",
                link: "today", actionable: false
            ))
        }
        // "After" photos: only for the latest procedure on each area.
        for area in Area.allCases {
            guard let p = Procedures.past(state, today: today.adding(1)).first(where: { $0.place == area }) else { continue }
            for w in Procedures.photoWeeks {
                let day = p.day.adding(w * 7)
                guard day >= today, day <= end, !state.dismissed.contains("proc:\(p.id):w\(w)") else { continue }
                // Already taken (photo day fell on the same day): nothing to ask.
                if state.photos.contains(where: { $0.place == area && $0.day >= day }) { continue }
                // A later session on this area is booked: its own before photo comes first.
                if state.procedures.contains(where: { $0.place == area && $0.day > p.day && $0.day <= day.adding(Procedures.aheadDays) }) { continue }
                let fire = DayTime(day, ClockTime(12, 0))
                guard fire.date(calendar: calendar) > now else { continue }
                out.append(PlannedReminder(
                    id: "\(day.iso):procphoto:\(p.id)", kind: .procedure, slot: nil, day: day, fire: fire, offsetMin: 0,
                    title: "\(Procedures.photoMark(w)) since \(p.name)",
                    body: "Today or tonight, a photo in the same light as your before one makes any change easier to see.",
                    link: "today", actionable: false
                ))
            }
        }
        return Array(out.sorted { $0.fire.date(calendar: calendar) < $1.fire.date(calendar: calendar) }.prefix(4))
    }
}
