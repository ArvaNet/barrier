import Foundation

// What changed and how it went, for the dermatologist: a change log of the
// routine, a weekly one-tap skin score, and the data for the timeline.

// MARK: - Routine changes

public struct PlanChange: Hashable, Sendable, Identifiable {
    public var day: Day
    /// "Tretinoin: every other night → every night".
    public var lines: [String]
    public var id: Int { day.ordinal }
}

public extension PlanSnapshot {
    /// The routine as it stands now.
    static func of(_ s: AppState, day: Day) -> PlanSnapshot {
        let products = Dictionary(s.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [SnapshotItem] = []
        var easing: [String: String] = [:]
        var names: [String: String] = [:]
        for slot in Slot.allCases {
            let sp = s.plan[slot]
            guard sp.enabled, !sp.steps.isEmpty else { continue }
            names[slot.rawValue] = slot == .body ? sp.displayName : slot.title
            if let e = sp.easeIn, !e.phases.isEmpty { easing[slot.rawValue] = e.start.adding(e.totalDays).iso }
            for step in sp.steps {
                guard let p = products[step.productId], !items.contains(where: { $0.slot == slot && $0.productID == p.id }) else { continue }
                let amount = step.amount?.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(SnapshotItem(slot: slot, productID: p.id, name: p.name, schedule: Engine.describe(step, in: sp, slot: slot),
                                          amount: amount?.isEmpty == false ? amount : nil, until: p.until))
            }
        }
        return PlanSnapshot(day: day, items: items, easing: easing, names: names)
    }

    /// Same routine, ignoring names (a typo fix isn't a change).
    func sameRoutine(as other: PlanSnapshot) -> Bool {
        func key(_ i: SnapshotItem) -> String { "\(i.slot.rawValue)|\(i.productID)|\(i.schedule)|\(i.amount ?? "")|\(i.until?.iso ?? "")" }
        return Set(items.map(key)) == Set(other.items.map(key)) && easing == other.easing && Set(names.keys) == Set(other.names.keys)
    }
}

public enum PlanHistory {
    /// Every day the routine changed, oldest first. The first snapshot is the starting routine.
    public static func changes(_ s: AppState) -> [PlanChange] {
        let current = Dictionary(s.products.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var out: [PlanChange] = []
        for (a, b) in zip(s.history, s.history.dropFirst()) {
            let lines = diff(a, b, names: current)
            if !lines.isEmpty { out.append(PlanChange(day: b.day, lines: lines)) }
        }
        return out
    }

    /// What changed from one snapshot to the next, in plain words.
    static func diff(_ a: PlanSnapshot, _ b: PlanSnapshot, names current: [String: String]) -> [String] {
        func name(_ i: SnapshotItem) -> String { current[i.productID] ?? i.name }
        func routine(_ slot: Slot, _ snap: PlanSnapshot) -> String { snap.names[slot.rawValue] ?? slot.title }
        var lines: [String] = []
        for slot in Slot.allCases {
            let old = a.items.filter { $0.slot == slot }
            let new = b.items.filter { $0.slot == slot }
            // A whole routine starting or stopping reads as one line.
            if old.isEmpty && !new.isEmpty && slot == .body {
                lines.append("\(routine(slot, b)) routine started: " + new.map(name).joined(separator: ", "))
                continue
            }
            if !old.isEmpty && new.isEmpty && slot == .body {
                lines.append("\(routine(slot, a)) routine stopped")
                continue
            }
            for n in new {
                guard let o = old.first(where: { $0.productID == n.productID }) else {
                    // In another routine before: it moved.
                    if let from = a.items.first(where: { $0.productID == n.productID && $0.slot != slot }),
                       !b.items.contains(where: { $0.productID == n.productID && $0.slot == from.slot }) {
                        lines.append("\(name(n)): moved from \(routine(from.slot, a).lowercased()) to \(routine(slot, b).lowercased()), \(n.schedule.lowercased())")
                    } else {
                        lines.append("\(name(n)): added to \(routine(slot, b).lowercased()), \(n.schedule.lowercased())")
                    }
                    continue
                }
                if o.schedule != n.schedule { lines.append("\(name(n)): \(o.schedule.lowercased()) → \(n.schedule.lowercased())") }
                if o.amount != n.amount {
                    switch (o.amount, n.amount) {
                    case let (x?, y?): lines.append("\(name(n)): \(x) → \(y)")
                    case let (nil, y?): lines.append("\(name(n)): amount \(y)")
                    default: break
                    }
                }
                if o.until != n.until {
                    lines.append(n.until.map { "\(name(n)): course until \($0.monthDay)" } ?? "\(name(n)): no end date")
                }
            }
            for o in old where !new.contains(where: { $0.productID == o.productID }) {
                // Moved items are reported once, where they arrived.
                let arrived = b.items.contains { n in
                    n.productID == o.productID && n.slot != slot && !a.items.contains { $0.productID == o.productID && $0.slot == n.slot }
                }
                if arrived { continue }
                lines.append("\(name(o)): stopped (\(routine(slot, a).lowercased()))")
            }
            let key = slot.rawValue
            if a.easing[key] == nil, b.easing[key] != nil, !new.isEmpty {
                lines.append("\(routine(slot, b)): easing in")
            } else if a.easing[key] != nil, b.easing[key] == nil, !new.isEmpty {
                lines.append("\(routine(slot, b)): ease-in removed")
            }
        }
        return lines
    }
}

public extension AppState {
    /// Note the routine as it stands today. Edits on the same day are one change,
    /// and a day whose edits undid themselves leaves no trace.
    mutating func recordPlan(today: Day) {
        let snap = PlanSnapshot.of(self, day: today)
        guard let last = history.last else {
            history = [snap]
            return
        }
        guard last.day <= today else { return }
        if last.sameRoutine(as: snap) {
            if last.day == today { history[history.count - 1] = snap } // keep the latest names
            return
        }
        if last.day == today {
            if history.count >= 2, history[history.count - 2].sameRoutine(as: snap) {
                history.removeLast()
            } else {
                history[history.count - 1] = snap
            }
        } else {
            history.append(snap)
        }
        if history.count > 200 { history.removeFirst(history.count - 200) }
    }
}

// MARK: - Weekly skin score

public enum Scores {
    public static let labels = ["Rough", "Not great", "Okay", "Good", "Great"]

    public static func label(_ value: Int) -> String { labels[min(5, max(1, value)) - 1] }

    public static func latest(_ s: AppState, area: Area) -> SkinScore? {
        s.scores.filter { $0.place == area }.max { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
    }

    /// About once a week; the first one right away, as a starting point.
    public static func isDue(_ s: AppState, area: Area, today: Day) -> Bool {
        guard let last = latest(s, area: area) else { return true }
        return last.day.days(to: today) >= 7
    }

    /// Areas to ask about: the face, and the body area when its routine is on.
    public static func areas(_ s: AppState) -> [Area] {
        s.plan.activeSlots.contains(.body) ? [.face, .body] : [.face]
    }
}

public extension AppState {
    /// One score per area per day; nil clears that day's.
    mutating func setScore(_ value: Int?, day: Day, area: Area, at: Date = Date()) {
        scores.removeAll { $0.day == day && $0.place == area }
        if let value { scores.append(SkinScore(day: day, value: value, area: area, at: at)) }
        scores.sort { $0.day == $1.day ? $0.place.rawValue < $1.place.rawValue : $0.day < $1.day }
        if scores.count > 600 { scores.removeFirst(scores.count - 600) }
    }
}

// MARK: - Timeline

/// Everything the timeline draws, one entry per day from `from` to `to`.
public struct TreatmentTimeline: Sendable {
    public enum Mark: Sendable, Equatable {
        case none
        /// Done, with a retinoid, acid or treatment in it.
        case activeDone
        /// Done, basics only (rest night, recovery night, a break).
        case basicsDone
        case activeMissed
        case basicsMissed
        /// Today, not done yet.
        case pending
    }

    public enum Skin: Int, Sendable, Comparable {
        case calm, symptoms, irritated
        public static func < (a: Skin, b: Skin) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Row: Sendable {
        public var slot: Slot
        public var name: String
        public var marks: [Mark]
    }

    public struct Band: Sendable, Equatable {
        public var from: Int
        public var to: Int
        public var label: String
    }

    public var from: Day
    public var to: Day
    public var rows: [Row]
    /// Worst of face and body, by day index.
    public var skin: [Int: Skin]
    /// (day index, 1…5), face (or body if the face has none).
    public var scores: [(day: Int, value: Int)]
    public var breaks: [Band]
    public var procedures: [(day: Int, name: String)]
    /// Routine changes in range, numbered from 1 in the order they happened.
    public var changes: [(day: Int, number: Int, change: PlanChange)]
    public var photos: [Int]

    public var days: Int { from.days(to: to) + 1 }

    public func index(_ d: Day) -> Int { from.days(to: d) }

    /// Up to `maxDays` ending today, starting no earlier than anything worth showing.
    public static func build(_ s: AppState, today: Day, maxDays: Int = 98) -> TreatmentTimeline {
        let earliest = today.adding(-(maxDays - 1))
        var starts = [s.plan.createdAt]
        starts += s.procedures.filter { $0.day >= earliest && $0.day <= today }.map(\.day)
        starts += s.photos.filter { $0.day >= earliest && $0.day <= today }.map(\.day)
        let from = max(earliest, min(starts.min() ?? today, today))
        var t = TreatmentTimeline(from: from, to: today, rows: [], skin: [:], scores: [], breaks: [], procedures: [], changes: [], photos: [])
        func ix(_ d: Day) -> Int { from.days(to: d) }

        for slot in Slot.allCases {
            let sp = s.plan[slot]
            let logged = s.log.contains { $0.slot == slot && $0.day >= from }
            guard (sp.enabled && !sp.steps.isEmpty) || logged else { continue }
            var marks = Array(repeating: Mark.none, count: t.days)
            for inst in Engine.timeline(s, slot: slot, from: from, to: today, today: today) {
                let i = ix(inst.day)
                guard i >= 0, i < marks.count, inst.day >= s.plan.createdAt else { continue }
                let active = inst.steps.contains(where: \.active)
                switch inst.status {
                case .done: marks[i] = active ? .activeDone : .basicsDone
                case .skipped, .unlogged: marks[i] = inst.steps.isEmpty ? .none : (active ? .activeMissed : .basicsMissed)
                case .pending: marks[i] = inst.steps.isEmpty ? .none : .pending
                case .future, .off: break
                }
            }
            if marks.contains(where: { $0 != .none }) {
                t.rows.append(Row(slot: slot, name: slot == .body ? sp.displayName : slot.title, marks: marks))
            }
        }

        for c in s.checkins where c.day >= from && c.day <= today {
            let level: Skin = c.feel.contains(where: \.isIrritation) ? .irritated : (c.feel.contains { $0 != .calm } ? .symptoms : .calm)
            let i = ix(c.day)
            t.skin[i] = max(t.skin[i] ?? .calm, level)
        }

        let faceScores = s.scores.filter { $0.place == .face && $0.day >= from && $0.day <= today }
        let use = faceScores.isEmpty ? s.scores.filter { $0.place == .body && $0.day >= from && $0.day <= today } : faceScores
        t.scores = use.sorted { $0.day < $1.day }.map { (ix($0.day), min(5, max(1, $0.value))) }

        for p in s.pauses where p.to >= from && p.from <= today {
            let label: String
            if p.procedureID != nil {
                label = "Actives break"
            } else {
                switch p.reason {
                case .travel: label = "Travel"
                case .irritation: label = "Skin break"
                case .procedure: label = "Procedure"
                case .sick: label = "Unwell"
                case .other: label = "Pause"
                }
            }
            t.breaks.append(Band(from: ix(max(p.from, from)), to: ix(min(p.to, today)), label: label))
        }
        t.breaks.sort { $0.from < $1.from }

        t.procedures = s.procedures.filter { $0.day >= from && $0.day <= today }.sorted { $0.day < $1.day }.map { (ix($0.day), $0.name) }
        let changes = PlanHistory.changes(s).filter { $0.day >= from && $0.day <= today }
        t.changes = changes.enumerated().map { (ix($0.element.day), $0.offset + 1, $0.element) }
        t.photos = Array(Set(s.photos.filter { $0.day >= from && $0.day <= today }.map { ix($0.day) })).sorted()
        return t
    }

    /// Done and due per row, for a one-line summary.
    public func counts(_ slot: Slot) -> (done: Int, due: Int) {
        guard let row = rows.first(where: { $0.slot == slot }) else { return (0, 0) }
        let done = row.marks.filter { $0 == .activeDone || $0 == .basicsDone }.count
        let due = row.marks.filter { $0 != .none && $0 != .pending }.count
        return (done, due)
    }
}
