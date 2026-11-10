import Foundation

// What changed and how it went, for the dermatologist: a change log of the
// routine, a weekly one-tap skin score, and the data for the timeline.

// MARK: - Routine changes

public struct PlanChange: Hashable, Sendable, Identifiable {
    public var day: Day
    /// "Tretinoin: every other night → every night".
    public var lines: [String]
    /// Counted from the start of the log, so it's the same number everywhere.
    public var number: Int = 0
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
            names[slot.rawValue] = slot.isBody ? s.plan.shortName(slot) : slot.title
            if let e = sp.easeIn, !e.phases.isEmpty { easing[slot.rawValue] = e.start.adding(e.totalDays).iso }
            for step in sp.steps {
                guard let p = products[step.productId], !items.contains(where: { $0.slot == slot && $0.productID == p.id }) else { continue }
                let amount = step.amount?.trimmingCharacters(in: .whitespacesAndNewlines)
                let goal = step.buildUp.flatMap { $0.done ? nil : Engine.everyPhrase($0.goal, word: slot.word) }
                items.append(SnapshotItem(slot: slot, productID: p.id, name: p.name, schedule: Engine.describe(step, in: sp, slot: slot),
                                          amount: amount?.isEmpty == false ? amount : nil, until: p.until,
                                          active: p.kind.isActive || p.kind == .oral, from: p.from, goal: goal))
            }
        }
        // What the replay needs, without the visit notes.
        var plan = s.plan
        plan.followUp = nil
        plan.ifIrritated = nil
        plan.dermNotes = nil
        let used = s.usedProductIDs
        let kept = s.products.filter { used.contains($0.id) }.sorted { $0.id < $1.id }
        return PlanSnapshot(day: day, items: items, easing: easing, names: names, plan: plan, products: kept)
    }

    /// Same routine for the log and the replay. A product rename is a new
    /// snapshot (the replay needs it), but only a strength change makes a line.
    func sameRoutine(as other: PlanSnapshot) -> Bool {
        func key(_ i: SnapshotItem) -> String {
            "\(i.slot.rawValue)|\(i.productID)|\(i.schedule)|\(i.amount ?? "")|\(i.until?.iso ?? "")|\(i.from?.iso ?? "")|\(PlanHistory.strength(i.name) ?? "")|\(i.goal ?? "")"
        }
        guard Set(items.map(key)) == Set(other.items.map(key)), easing == other.easing, Set(names.keys) == Set(other.names.keys) else { return false }
        if let p = plan, let q = other.plan, p != q { return false }
        if let p = products, let q = other.products, p != q { return false }
        return true
    }
}

public enum PlanHistory {
    /// Every day the routine changed, oldest first, numbered from 1.
    /// The first snapshot is the starting routine.
    public static func changes(_ s: AppState) -> [PlanChange] {
        var out: [PlanChange] = []
        for (a, b) in zip(s.history, s.history.dropFirst()) {
            let lines = diff(a, b)
            if !lines.isEmpty { out.append(PlanChange(day: b.day, lines: lines, number: out.count + 1)) }
        }
        return out
    }

    /// "0.025%" from "Tretinoin 0.025% cream".
    static func strength(_ name: String) -> String? {
        guard let r = name.range(of: #"\d+([.,]\d+)?\s*%"#, options: .regularExpression) else { return nil }
        return name[r].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
    }

    static func norm(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The name without its strength: "Tretinoin 0.025% cream" → "tretinoin cream".
    static func base(_ s: String) -> String {
        norm(s.replacingOccurrences(of: #"\d+([.,]\d+)?\s*%"#, with: " ", options: .regularExpression))
    }

    /// The same product, even when removed and added again (a new id) or given a new strength.
    static func same(_ x: SnapshotItem, _ y: SnapshotItem) -> Bool {
        x.productID == y.productID || norm(x.name) == norm(y.name) || base(x.name) == base(y.name)
    }

    /// "every night", but "Mon, Wed, Fri" as it was.
    public static func lowered(_ schedule: String) -> String {
        guard schedule.hasPrefix("Every ") || schedule.hasPrefix("Not ") else { return schedule }
        return schedule.prefix(1).lowercased() + schedule.dropFirst()
    }

    /// "Pea-size" → "pea-size", but "SPF" stays.
    static func lowerFirst(_ s: String) -> String {
        let chars = Array(s)
        if chars.count > 1, chars[0].isUppercase, chars[1].isUppercase { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
    }

    /// "morning", "evening", or the body routine's own name as written.
    static func routine(_ slot: Slot, _ snap: PlanSnapshot) -> String {
        switch slot {
        case .am: return "morning"
        case .pm: return "evening"
        case .body, .body2: return snap.names[slot.rawValue] ?? "Body"
        }
    }

    /// What changed from one snapshot to the next, in plain words, product first.
    static func diff(_ a: PlanSnapshot, _ b: PlanSnapshot) -> [String] {
        var lines: [String] = []
        for slot in Slot.allCases {
            let old = a.items.filter { $0.slot == slot }
            let new = b.items.filter { $0.slot == slot }

            // Pair old and new: same id first, then the same name, then the same name at another strength.
            var restOld = old
            var pairs: [(SnapshotItem, SnapshotItem)] = []
            var restNew: [SnapshotItem] = []
            var unpaired = new
            for match in [{ (o: SnapshotItem, n: SnapshotItem) in o.productID == n.productID },
                          { (o: SnapshotItem, n: SnapshotItem) in norm(o.name) == norm(n.name) },
                          { (o: SnapshotItem, n: SnapshotItem) in base(o.name) == base(n.name) }] {
                var still: [SnapshotItem] = []
                for n in unpaired {
                    if let i = restOld.firstIndex(where: { match($0, n) }) {
                        pairs.append((restOld.remove(at: i), n))
                    } else {
                        still.append(n)
                    }
                }
                unpaired = still
            }
            restNew = unpaired

            // Arrived from another routine, which no longer has it.
            func movedIn(_ n: SnapshotItem) -> SnapshotItem? {
                a.items.first { o in o.slot != slot && same(o, n) && !b.items.contains { $0.slot == o.slot && same(o, $0) } }
            }
            // Left for another routine, which didn't have it.
            func movedOut(_ o: SnapshotItem) -> Bool {
                b.items.contains { n in n.slot != slot && same(o, n) && !a.items.contains { $0.slot == n.slot && same(n, $0) } }
            }

            // A body routine starting or stopping reads as one line.
            if slot.isBody && old.isEmpty && !new.isEmpty {
                lines.append("\(routine(slot, b)) routine started: " + new.map { "\($0.name), \(lowered($0.schedule))" }.joined(separator: "; "))
                for n in new { if let from = movedIn(n) { lines.append("\(n.name): moved from \(routine(from.slot, a))") } }
                continue
            }
            if slot.isBody && !old.isEmpty && new.isEmpty {
                lines.append("\(routine(slot, a)) routine stopped")
                continue
            }

            for (o, n) in pairs {
                if let s1 = strength(o.name), let s2 = strength(n.name), s1 != s2 {
                    lines.append("\(Product.shortName(n.name)): \(s1) → \(s2)")
                }
                switch (o.goal, n.goal) {
                case (nil, _?) where a.easing[slot.rawValue] != nil:
                    // The routine's ease-in, now set on the product: the same plan, not a change.
                    break
                case (nil, let g?):
                    lines.append("\(n.name): starting slowly, \(lowered(n.schedule)), building up to \(lowered(g))")
                case (_?, let g?) where o.schedule != n.schedule:
                    lines.append("\(n.name): moved up to \(lowered(n.schedule)), building up to \(lowered(g))")
                case (_?, nil):
                    lines.append(o.goal.map(lowered) == lowered(n.schedule)
                                 ? "\(n.name): now \(lowered(n.schedule)), build-up done"
                                 : "\(n.name): build-up stopped, \(lowered(n.schedule))")
                default:
                    if o.schedule != n.schedule { lines.append("\(n.name): \(lowered(o.schedule)) → \(lowered(n.schedule))") }
                }
                switch (o.amount, n.amount) {
                case let (x?, y?) where x != y: lines.append("\(n.name): amount \(lowerFirst(x)) → \(lowerFirst(y))")
                case let (nil, y?): lines.append("\(n.name): amount set to \(lowerFirst(y))")
                case (_?, nil): lines.append("\(n.name): amount removed")
                default: break
                }
                if o.until != n.until {
                    lines.append(n.until.map { "\(n.name): course until \($0.monthDay)" } ?? "\(n.name): no end date")
                }
                if o.from != n.from, let f = n.from, f > b.day {
                    lines.append("\(n.name): start moved to \(f.monthDay)")
                }
            }
            for n in restNew {
                if let from = movedIn(n) {
                    lines.append("\(n.name): moved from \(routine(from.slot, a)) to \(routine(slot, b)), \(lowered(n.schedule))")
                    continue
                }
                let start = n.from.flatMap { $0 > b.day ? ", from \($0.monthDay)" : nil } ?? ""
                let building = n.goal.map { ", building up to \(lowered($0))" } ?? ""
                if !slot.isBody, n.schedule.lowercased().contains(slot.word) {
                    lines.append("\(n.name): started, \(lowered(n.schedule))\(building)\(start)")
                } else {
                    let place = slot.isBody ? "the \(routine(slot, b)) routine" : "the \(routine(slot, b))"
                    lines.append("\(n.name): started in \(place), \(lowered(n.schedule))\(building)\(start)")
                }
            }
            for o in restOld where !movedOut(o) {
                lines.append("\(o.name): stopped (\(routine(slot, a)))")
            }

            let key = slot.rawValue
            let title = slot.isBody ? routine(slot, b) : slot.title
            if a.easing[key] == nil, let end = b.easing[key], !new.isEmpty {
                let date = Day(iso: end).map { ", full routine from \($0.monthDay)" } ?? ""
                lines.append("\(title): easing in\(date)")
            } else if let end = a.easing[key], b.easing[key] == nil, !new.isEmpty,
                      !new.contains(where: { $0.goal != nil }), Day(iso: end).map({ $0 > b.day }) ?? true {
                // An ease-in now set per product, or one that had already finished, isn't a removal.
                lines.append("\(title): ease-in removed")
            }
        }
        return lines
    }
}

public extension AppState {
    /// Note the routine as it stands today. Edits on the same day are one change,
    /// and a day whose edits undid themselves leaves no trace. `start`: an older
    /// save opening for the first time (that day's edits still count).
    mutating func recordPlan(today: Day, start: Bool = false) {
        var snap = PlanSnapshot.of(self, day: today)
        if start { snap.start = true }
        guard !history.isEmpty else {
            history = [snap]
            return
        }
        // Dated ahead (the clock was set forward, then back): it belongs to today.
        if history[history.count - 1].day > today {
            history[history.count - 1].day = today
            while history.count >= 2, history[history.count - 2].day >= today { history.remove(at: history.count - 2) }
        }
        let last = history[history.count - 1]
        let sameDay = last.day == today && last.start != true
        if last.sameRoutine(as: snap) {
            if sameDay { history[history.count - 1] = snap }
            return
        }
        if sameDay {
            if history.count >= 2, history[history.count - 2].sameRoutine(as: snap) {
                history.removeLast()
            } else {
                history[history.count - 1] = snap
            }
        } else {
            history.append(snap)
        }
        if history.count > 120 { history.removeFirst(history.count - 120) }
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
        s.plan.activeSlots.contains(where: \.isBody) ? [.face, .body] : [.face]
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
        /// Done, with a retinoid, acid, treatment or medication in it.
        case activeDone
        /// Done, basics only (rest night, recovery night, a break).
        case basicsDone
        case activeMissed
        case basicsMissed
        /// Today, not done yet.
        case pending

        public var isMissed: Bool { self == .activeMissed || self == .basicsMissed }
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
        /// nil = every routine.
        public var area: Area?
    }

    public var from: Day
    public var to: Day
    public var rows: [Row]
    /// Face check-ins by day index.
    public var skin: [Int: Skin]
    /// Body check-ins by day index (a row of its own).
    public var bodySkin: [Int: Skin] = [:]
    /// (day index, 1…5), face (or body if the face has none).
    public var scores: [(day: Int, value: Int)]
    public var breaks: [Band]
    /// "Subcision 1/3".
    public var procedures: [(day: Int, name: String)]
    /// Routine changes in range, numbered from the start of the log.
    public var changes: [(day: Int, number: Int, change: PlanChange)]
    public var photos: [Int]
    /// Procedures from before the timeline starts, latest first (two at most).
    public var earlier: [(day: Day, name: String)] = []
    /// Days at the start before the routine began ("Before Tendwell").
    public var beforeDays: Int = 0
    /// The body routine's name, for the back skin row and break labels.
    public var bodyName: String = "Body"

    public var days: Int { from.days(to: to) + 1 }

    public func index(_ d: Day) -> Int { from.days(to: d) }

    public var showsBodySkin: Bool { rows.contains { $0.slot.isBody } || !bodySkin.isEmpty }

    /// The routine's start (or an event in the two weeks before it) to today:
    /// at least `minDays` so a new routine isn't drawn as giant blocks, at most `maxDays`.
    public static func build(_ s: AppState, today: Day, maxDays: Int = 98, minDays: Int = 14) -> TreatmentTimeline {
        let created = s.plan.createdAt
        var start = created
        let lead = created.adding(-14)
        let events = s.procedures.map(\.day) + s.photos.map(\.day)
        if let first = events.filter({ $0 >= lead && $0 < created }).min() { start = first }
        let from = max(today.adding(-(maxDays - 1)), min(start, today.adding(-(minDays - 1))))
        var t = TreatmentTimeline(from: from, to: today, rows: [], skin: [:], scores: [], breaks: [], procedures: [], changes: [], photos: [])
        func ix(_ d: Day) -> Int { from.days(to: d) }
        t.beforeDays = max(0, min(t.days, from.days(to: created)))
        t.bodyName = s.plan.body.displayName

        // Each stretch of days replays with the plan it had (from the change log):
        // today's plan replayed over the past would misdraw everything before an edit.
        func stateFor(_ snap: PlanSnapshot) -> AppState {
            guard let plan = snap.plan else { return s }
            var c = s
            c.plan = plan
            c.plan.createdAt = s.plan.createdAt
            if let prods = snap.products {
                var byID = Dictionary(s.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                for p in prods { byID[p.id] = p }
                c.products = Array(byID.values)
            }
            return c
        }
        var stretches: [(lo: Day, hi: Day, state: AppState)] = []
        let snaps = s.history
        if snaps.isEmpty {
            stretches = [(from, today, s)]
        } else {
            for (i, snap) in snaps.enumerated() {
                let a = i == 0 ? min(from, snap.day) : snap.day
                let b = i + 1 < snaps.count ? snaps[i + 1].day.adding(-1) : today
                let lo = max(a, from), hi = min(b, today)
                guard lo <= hi else { continue }
                stretches.append((lo, hi, i == snaps.count - 1 ? s : stateFor(snap)))
            }
        }

        // Evening first: it's usually where the treatment is.
        for slot in Slot.ordered {
            var marks = Array(repeating: Mark.none, count: t.days)
            for stretch in stretches {
                for inst in Engine.timeline(stretch.state, slot: slot, from: stretch.lo, to: stretch.hi, today: today) {
                    let i = ix(inst.day)
                    guard i >= 0, i < marks.count, inst.day >= created else { continue }
                    // A night done without its treatment (only some steps ticked) reads as basics.
                    let ticked = inst.entry?.steps.map(Set.init)
                    let active = inst.steps.contains { ($0.product.kind.isActive || $0.product.kind == .oral) && (ticked?.contains($0.step.id) ?? true) }
                    switch inst.status {
                    case .done: marks[i] = active ? .activeDone : .basicsDone
                    case .skipped, .unlogged: marks[i] = inst.steps.isEmpty ? .none : (active ? .activeMissed : .basicsMissed)
                    case .pending: marks[i] = inst.steps.isEmpty ? .none : .pending
                    case .future, .off: break
                    }
                }
            }
            if marks.contains(where: { $0 != .none }) {
                let sp = s.plan[slot]
                t.rows.append(Row(slot: slot, name: slot.isBody ? s.plan.shortName(slot) : slot.title, marks: marks))
            }
        }

        for c in s.checkins where c.day >= from && c.day <= today {
            let level: Skin = c.feel.contains(where: \.isIrritation) ? .irritated : (c.feel.contains { $0 != .calm } ? .symptoms : .calm)
            let i = ix(c.day)
            if c.place == .body {
                t.bodySkin[i] = max(t.bodySkin[i] ?? .calm, level)
            } else {
                t.skin[i] = max(t.skin[i] ?? .calm, level)
            }
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
            t.breaks.append(Band(from: ix(max(p.from, from)), to: ix(min(p.to, today)), label: label, area: p.area))
        }
        t.breaks.sort { $0.from < $1.from }

        t.procedures = s.procedures.filter { $0.day >= from && $0.day <= today }.sorted { $0.day < $1.day }.map { p in
            let session = p.session.map { n in p.sessions.map { " \(n)/\($0)" } ?? " \(n)" } ?? ""
            return (ix(p.day), p.name + session)
        }
        t.changes = PlanHistory.changes(s).filter { $0.day >= from && $0.day <= today }.map { (ix($0.day), $0.number, $0) }
        t.photos = Array(Set(s.photos.filter { $0.day >= from && $0.day <= today }.map { ix($0.day) })).sorted()
        t.earlier = s.procedures.filter { $0.day < from }.sorted { $0.day > $1.day }.prefix(2).map { ($0.day, $0.name) }
        return t
    }

    /// Done and due per row, the same numbers the strip shows.
    public func counts(_ slot: Slot) -> (done: Int, due: Int) {
        guard let row = rows.first(where: { $0.slot == slot }) else { return (0, 0) }
        let done = row.marks.filter { $0 == .activeDone || $0 == .basicsDone }.count
        let due = row.marks.filter { $0 != .none && $0 != .pending }.count
        return (done, due)
    }
}
