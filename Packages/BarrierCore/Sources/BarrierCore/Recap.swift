import Foundation

/// A short look back at last week, shown on Mondays. Facts only, no grades.
public struct WeekRecap: Hashable, Sendable {
    public var id: String
    public var from: Day
    public var to: Day
    public var nightsDone: Int
    public var nightsDue: Int
    public var morningsDone: Int
    public var irritationDays: Int
    public var calmDays: Int
    public var checkIns: Int
    public var photos: Int
    public var recoveryNights: Int

    public var headline: String {
        if nightsDue == 0 { return "A quiet week" }
        if nightsDone == nightsDue { return "Every night, last week" }
        return "\(nightsDone) of \(nightsDue) nights last week"
    }

    public var lines: [String] {
        var out: [String] = []
        if checkIns > 0 {
            if irritationDays == 0 {
                out.append(calmDays > 0 ? "Skin: calm on \(calmDays) of \(checkIns) check-ins, no irritation." : "Skin: no irritation logged.")
            } else {
                out.append("Skin: \(irritationDays) irritated day\(irritationDays == 1 ? "" : "s") out of \(checkIns) check-ins.")
            }
        }
        if recoveryNights > 0 { out.append("\(recoveryNights) recovery night\(recoveryNights == 1 ? "" : "s") when skin needed it.") }
        if morningsDone > 0 { out.append("\(morningsDone) morning\(morningsDone == 1 ? "" : "s") logged.") }
        out.append(photos > 0 ? "\(photos) progress photo\(photos == 1 ? "" : "s") taken." : "No photo last week. This week’s is a good one to take.")
        return out
    }
}

public enum Recaps {
    /// Last Monday–Sunday, if today is Monday or Tuesday and the plan is older than that week's start.
    public static func lastWeek(_ state: AppState, today: Day) -> WeekRecap? {
        let wd = today.weekday // 1 = Monday
        guard wd == 1 || wd == 2 else { return nil }
        let thisMonday = today.adding(-(wd - 1))
        let from = thisMonday.adding(-7)
        let to = thisMonday.adding(-1)
        guard state.plan.createdAt <= from.adding(3) else { return nil }
        var r = WeekRecap(id: "recap-\(from.iso)", from: from, to: to, nightsDone: 0, nightsDue: 0, morningsDone: 0,
                          irritationDays: 0, calmDays: 0, checkIns: 0, photos: 0, recoveryNights: 0)
        if state.plan.pm.enabled {
            let start = max(from, state.plan.createdAt)
            if start <= to {
                for i in Engine.timeline(state, slot: .pm, from: start, to: to, today: today) where i.status != .off && !i.steps.isEmpty {
                    r.nightsDue += 1
                    if i.status == .done { r.nightsDone += 1 }
                    if i.rest == .inserted { r.recoveryNights += 1 }
                }
            }
        }
        r.morningsDone = state.log.filter { $0.slot == .am && $0.status == .done && $0.day >= from && $0.day <= to }.count
        for c in state.checkins where c.day >= from && c.day <= to {
            r.checkIns += 1
            if c.feel.contains(where: \.isIrritation) { r.irritationDays += 1 }
            if c.feel.contains(.calm) { r.calmDays += 1 }
        }
        r.photos = state.photos.filter { $0.day >= from && $0.day <= to }.count
        return r
    }
}
