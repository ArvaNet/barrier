import Foundation

// The schedule engine. Pure functions: state in, answers out.
//
// A slot (morning or evening) runs a rotation of `length` positions. The
// rotation advances one position per night that actually happened. A night
// with actives that was skipped or never logged does NOT advance it, so the
// next night picks up where you left off ("Barrier never skips ahead").
// Nights without actives (recovery) advance even when unlogged: the skin
// rested either way.

public struct DueStep: Hashable, Sendable {
    public var step: Step
    public var product: Product
    public var active: Bool { product.kind.isActive }
}

public enum RestReason: String, Sendable {
    /// A recovery position in the rotation (ease-in).
    case rotation
    /// Turned into a recovery night by the user (irritation).
    case inserted
    /// Inside a pause (travel etc.).
    case pause
}

public enum InstanceStatus: String, Sendable {
    case done, skipped, pending, future
    /// In the past, nothing logged.
    case unlogged
    /// Slot disabled, or before the plan existed.
    case off
}

public enum ConflictID: String, Sendable, CaseIterable {
    case retinoidExfoliant = "retinoid+exfoliant"
    case bpoTretinoin = "bpo+tretinoin"
}

/// One morning or one night: what's due and how it went.
public struct Instance: Hashable, Sendable, Identifiable {
    public var id: String { "\(day.iso)-\(slot.rawValue)" }
    public var day: Day
    public var slot: Slot
    public var pos: Int
    public var cycleLen: Int
    public var length: Int
    public var rest: RestReason?
    public var steps: [DueStep]
    public var label: String
    public var hue: Hue
    public var entry: Entry?
    public var status: InstanceStatus
    public var hasActives: Bool
    public var conflicts: [ConflictID]
    /// Ease-in phase index; phases.count means the full plan.
    public var phase: Int
    public var easing: Bool
    /// Products whose course ends on this day.
    public var lastDayOf: [Product]

    public var isDone: Bool { status == .done }
    public var isResolved: Bool { status == .done || status == .skipped }
    public var totalWait: Int { steps.reduce(0) { $0 + ($1.step.waitMin ?? 0) } }
}

public enum Engine {
    // MARK: Building blocks

    public static func phase(_ sp: SlotPlan, on day: Day) -> (index: Int, extraRest: Int) {
        guard let ease = sp.easeIn, !ease.phases.isEmpty else { return (0, 0) }
        var d = max(0, ease.start.days(to: day))
        for (i, p) in ease.phases.enumerated() {
            if d < p.days { return (i, p.extraRest) }
            d -= p.days
        }
        return (ease.phases.count, 0)
    }

    public static func cycleLen(_ sp: SlotPlan, on day: Day) -> Int {
        max(1, sp.length) + phase(sp, on: day).extraRest
    }

    public static func isPaused(_ state: AppState, _ day: Day) -> Bool {
        state.pauses.contains { $0.from <= day && day <= $0.to }
    }

    public static func activePause(_ state: AppState, _ day: Day) -> Pause? {
        state.pauses.first { $0.from <= day && day <= $0.to }
    }

    static func inWindow(_ p: Product, _ day: Day) -> Bool {
        if let f = p.from, day < f { return false }
        if let u = p.until, day > u { return false }
        return true
    }

    /// Steps due on a day at a rotation position. Rest mode drops actives.
    public static func dueSteps(_ sp: SlotPlan, products: [String: Product], day: Day, pos: Int, restMode: Bool) -> [DueStep] {
        let restPos = pos >= sp.length
        let wd = day.weekday
        var out: [DueStep] = []
        for step in sp.steps {
            guard let product = products[step.productId], inWindow(product, day) else { continue }
            let due: Bool
            switch step.on {
            case .all: due = true
            case .nights(let n): due = !restPos && n.contains(pos)
            case .weekdays(let d): due = d.contains(wd)
            }
            guard due else { continue }
            if (restMode || restPos) && product.kind.isActive { continue }
            out.append(DueStep(step: step, product: product))
        }
        return out
    }

    /// Whether a base position (ignoring weekday steps and windows) carries actives.
    static func positionHasActives(_ sp: SlotPlan, products: [String: Product], pos: Int) -> Bool {
        guard pos < sp.length else { return false }
        return sp.steps.contains { s in
            guard let p = products[s.productId], p.kind.isActive else { return false }
            switch s.on {
            case .all: return true
            case .nights(let n): return n.contains(pos)
            case .weekdays: return false
            }
        }
    }

    public static func label(slot: Slot, steps: [DueStep], rest: RestReason?, sp: SlotPlan, pos: Int, products: [String: Product]) -> (label: String, hue: Hue) {
        let word = slot.word
        if rest == .pause { return ("Simple \(word)", slot == .pm ? .mist : .dawn) }
        if rest == .inserted { return (slot == .pm ? "Recovery night" : "Gentle morning", .sage) }
        let custom = sp.names?[String(pos)].flatMap { $0.isEmpty ? nil : $0 }
        let actives = steps.filter(\.active)
        let has: (ProductKind) -> Bool = { k in actives.contains { $0.product.kind == k } }
        var label: String
        var hue: Hue
        if slot == .am && sp.length == 1 {
            // Same every morning: name it plainly.
            label = "Morning routine"
            hue = .dawn
        } else if has(.retinoid) && has(.exfoliant) {
            label = "Retinoid + exfoliant \(word)"
            hue = .clay
        } else if has(.retinoid) {
            label = "Retinoid \(word)"
            hue = .clay
        } else if has(.exfoliant) {
            label = "Exfoliation \(word)"
            hue = .gold
        } else if actives.count == 1 {
            label = "\(actives[0].product.shortName) \(word)"
            hue = .rose
        } else if actives.count > 1 {
            label = "Treatment \(word)"
            hue = .rose
        } else if slot == .am {
            label = "Morning routine"
            hue = .dawn
        } else {
            label = "Recovery night"
            // A second recovery night in a row reads as "mist", like skin cycling's night 4.
            let prev = pos - 1
            let prevIsRest = sp.length > 1 && prev >= 0 && !positionHasActives(sp, products: products, pos: prev)
            hue = prevIsRest ? .mist : .sage
        }
        return (custom ?? label, hue)
    }

    public static func conflicts(_ steps: [DueStep]) -> [ConflictID] {
        var out: [ConflictID] = []
        let kinds = Set(steps.map(\.product.kind))
        if kinds.contains(.retinoid) && kinds.contains(.exfoliant) { out.append(.retinoidExfoliant) }
        let hasBpo = steps.contains { $0.product.name.lowercased().contains("benzoyl") }
        let hasTret = steps.contains {
            $0.product.kind == .retinoid && $0.product.name.range(of: #"tretinoin|retin-?a"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if hasBpo && hasTret { out.append(.bpoTretinoin) }
        return out
    }

    static func entryIndex(_ log: [Entry]) -> [String: Entry] {
        var m: [String: Entry] = [:]
        for e in log { m["\(e.day.iso)|\(e.slot.rawValue)"] = e }
        return m
    }

    // MARK: Timeline

    /// Every instance of a slot from `from` to `to` (inclusive). Past days replay
    /// the log; today and later are projected assuming each night happens.
    public static func timeline(_ state: AppState, slot: Slot, from: Day, to: Day, today: Day) -> [Instance] {
        let sp = state.plan[slot]
        let products = Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = entryIndex(state.log)
        let entry: (Day) -> Entry? = { entries["\($0.iso)|\(slot.rawValue)"] }
        var out: [Instance] = []
        let anchor = sp.anchor
        let totalPhases = sp.easeIn?.phases.count ?? 0

        // Days before the anchor: history snapshots only.
        var d = from
        while d <= to && d < anchor.day {
            let e = entry(d)
            let status: InstanceStatus = e.map { $0.status == .done ? .done : ($0.status == .skipped ? .skipped : .off) } ?? .off
            out.append(Instance(
                day: d, slot: slot, pos: e?.pos ?? 0, cycleLen: sp.length, length: sp.length, rest: nil, steps: [],
                label: e?.label ?? "", hue: e?.hue ?? .sage, entry: e, status: status, hasActives: false,
                conflicts: [], phase: 0, easing: false, lastDayOf: []
            ))
            d = d.adding(1)
        }

        var pos = anchor.pos
        d = anchor.day
        while d <= to {
            let ph = phase(sp, on: d)
            let cl = max(1, sp.length) + ph.extraRest
            if pos >= cl || pos < 0 { pos = 0 }

            let e = entry(d)
            let paused = isPaused(state, d)
            let restPos = pos >= sp.length
            let rest: RestReason? = paused ? .pause : (e?.recovery == true ? .inserted : (restPos ? .rotation : nil))
            let full = dueSteps(sp, products: products, day: d, pos: pos, restMode: false)
            let hasActives = full.contains(where: \.active)
            let steps = rest != nil ? dueSteps(sp, products: products, day: d, pos: pos, restMode: true) : full

            if d >= from {
                let (label, hue) = self.label(slot: slot, steps: steps, rest: rest, sp: sp, pos: pos, products: products)
                let status: InstanceStatus
                if !sp.enabled { status = .off }
                else if e?.status == .done { status = .done }
                else if e?.status == .skipped { status = .skipped }
                else if d < today { status = .unlogged }
                else if d == today { status = .pending }
                else { status = .future }
                let ending = state.products.filter { p in p.until == d && steps.contains { $0.product.id == p.id } }
                out.append(Instance(
                    day: d, slot: slot, pos: pos, cycleLen: cl, length: sp.length, rest: rest, steps: steps,
                    label: label, hue: hue, entry: e, status: status, hasActives: hasActives && rest == nil,
                    conflicts: conflicts(steps), phase: ph.index, easing: totalPhases > 0 && ph.index < totalPhases,
                    lastDayOf: ending
                ))
            }

            // Advance the rotation for the next day.
            if sp.enabled && !paused && e?.recovery != true {
                let needsLog = hasActives && !restPos
                let advance: Bool
                if d < today { advance = e?.status == .done || !needsLog }
                else if d == today { advance = e?.status != .skipped || !needsLog }
                else { advance = true }
                if advance { pos = (pos + 1) % cl }
            }
            d = d.adding(1)
        }
        return out
    }

    public static func instance(_ state: AppState, slot: Slot, on day: Day, today: Day) -> Instance {
        timeline(state, slot: slot, from: day, to: day, today: today)[0]
    }

    /// Past nights with actives that were never logged, earliest first (max 2 days back).
    /// Only rotations ask: on a same-every-time routine the answer changes nothing.
    public static func needsReconcile(_ state: AppState, today: Day) -> [Instance] {
        var out: [Instance] = []
        for slot in [Slot.pm, .am] where state.plan[slot].enabled {
            let from = max(today.adding(-2), state.plan.createdAt)
            let to = today.adding(-1)
            guard from <= to else { continue }
            for i in timeline(state, slot: slot, from: from, to: to, today: today) where i.status == .unlogged && i.hasActives && i.cycleLen > 1 {
                out.append(i)
            }
        }
        return out.sorted { a, b in a.day == b.day ? (a.slot == .am) : a.day < b.day }
    }

    /// The next day (after `today`) when a step matching `match` is due.
    public static func next(_ state: AppState, slot: Slot, today: Day, horizon: Int = 21, where match: (DueStep) -> Bool) -> Instance? {
        timeline(state, slot: slot, from: today.adding(1), to: today.adding(horizon), today: today)
            .first { $0.steps.contains(where: match) }
    }

    /// Every position of the rotation as it stands on a day (for the orbit).
    public static func rotationNodes(_ state: AppState, slot: Slot, on day: Day) -> [(pos: Int, label: String, hue: Hue, rest: Bool)] {
        let sp = state.plan[slot]
        let products = Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let cl = cycleLen(sp, on: day)
        return (0..<cl).map { i in
            let rest = i >= sp.length
            let steps = dueSteps(sp, products: products, day: day, pos: i, restMode: rest)
            let l = label(slot: slot, steps: steps, rest: rest ? .rotation : nil, sp: sp, pos: i, products: products)
            return (i, l.label, l.hue, rest)
        }
    }

    // MARK: Stats

    public struct Stats: Sendable {
        public var nightsDone = 0
        public var morningsDone = 0
        public var last28Done = 0
        public var last28Due = 0
        public var firstDay: Day?
        public var byLabel: [String: Int] = [:]
        public var skipped = 0
        public var recoveryNights = 0
    }

    public static func stats(_ state: AppState, today: Day) -> Stats {
        var s = Stats()
        for e in state.log {
            if e.recovery == true && e.slot == .pm { s.recoveryNights += 1 }
            if e.status == .skipped && e.slot == .pm { s.skipped += 1 }
            guard e.status == .done else { continue }
            if e.slot == .pm { s.nightsDone += 1 } else { s.morningsDone += 1 }
            if s.firstDay == nil || e.day < s.firstDay! { s.firstDay = e.day }
            if e.slot == .pm, let l = e.label { s.byLabel[l, default: 0] += 1 }
        }
        let from = max(today.adding(-27), state.plan.createdAt)
        if state.plan.pm.enabled && from <= today {
            for i in timeline(state, slot: .pm, from: from, to: today, today: today) {
                if i.status == .off || i.status == .pending { continue }
                s.last28Due += 1
                if i.status == .done { s.last28Done += 1 }
            }
        }
        return s
    }

    public struct Ring: Hashable, Sendable {
        public var from: Day
        public var to: Day
        public var segments: [Segment]

        public struct Segment: Hashable, Sendable {
            public var hue: Hue
            public var done: Bool
            public var day: Day
        }
    }

    /// Growth rings: one per rotation cycle when the rotation is 3+ nights,
    /// otherwise one per week (Monday start). The newest ring is last.
    public static func rings(_ state: AppState, today: Day, max: Int = 26) -> [Ring] {
        let sp = state.plan.pm
        let start = state.plan.createdAt
        guard sp.enabled, start <= today else { return [] }
        let tl = timeline(state, slot: .pm, from: start, to: today, today: today)
        var out: [Ring] = []
        let byCycle = sp.length >= 3
        for inst in tl {
            // Before the anchor (an earlier plan), only logged nights know their position.
            let known = inst.day >= sp.anchor.day || inst.entry != nil
            let boundary = byCycle ? (inst.pos == 0 && inst.rest == nil && known) : inst.day.weekday == 1
            if out.isEmpty || (boundary && !(out.last!.segments.isEmpty)) {
                out.append(Ring(from: inst.day, to: inst.day, segments: []))
            }
            out[out.count - 1].to = inst.day
            out[out.count - 1].segments.append(.init(hue: inst.hue, done: inst.status == .done, day: inst.day))
        }
        return Array(out.suffix(max))
    }

    // MARK: Editing helpers

    public static func lcm(_ a: Int, _ b: Int) -> Int {
        func gcd(_ x: Int, _ y: Int) -> Int { y == 0 ? x : gcd(y, x % y) }
        return a / gcd(a, b) * b
    }

    /// Positions a step is on within the base rotation.
    public static func nights(of step: Step, length: Int) -> [Int] {
        switch step.on {
        case .all: return Array(0..<length)
        case .nights(let n): return n.filter { $0 < length }
        case .weekdays: return []
        }
    }

    /// Change the rotation length, keeping each step's pattern
    /// (every other night stays every other night).
    public static func resize(_ sp: SlotPlan, to newLength: Int) -> SlotPlan {
        let old = max(1, sp.length)
        var plan = sp
        plan.steps = sp.steps.map { s in
            guard case .nights(let n) = s.on else { return s }
            let set = Set(n)
            var copy = s
            copy.on = .nights((0..<newLength).filter { set.contains($0 % old) })
            return copy
        }
        plan.length = newLength
        plan.names = nil
        return plan
    }

    public static let maxRotation = 12

    /// Put a step on "every Nth night", choosing the offset that collides
    /// least with other actives. Grows the rotation if needed, up to
    /// `maxRotation`. Returns nil when the pattern can't fit without breaking
    /// another step's spacing.
    public static func setEvery(_ sp: SlotPlan, stepID: String, n: Int, products: [String: Product]) -> SlotPlan? {
        var plan = sp
        if n <= 1 {
            plan.steps = plan.steps.map { s in
                var c = s
                if s.id == stepID { c.on = .all }
                return c
            }
            return plan
        }
        let want = lcm(max(1, plan.length), n)
        if want > maxRotation { return nil }
        if want != plan.length { plan = resize(plan, to: want) }
        let L = plan.length
        var usage = Array(repeating: 0, count: L)
        for s in plan.steps where s.id != stepID {
            guard let p = products[s.productId], p.kind.isActive else { continue }
            for i in nights(of: s, length: L) { usage[i] += 1 }
        }
        var best = 0
        var bestScore = Int.max
        for off in 0..<n {
            var score = 0
            var i = off
            while i < L {
                score += usage[i]
                i += n
            }
            if score < bestScore {
                bestScore = score
                best = off
            }
        }
        let nights = stride(from: best, to: L, by: n).map { $0 }
        plan.steps = plan.steps.map { s in
            var c = s
            if s.id == stepID { c.on = .nights(nights) }
            return c
        }
        return plan
    }

    /// If a step is regularly spaced, its spacing (1 = every night).
    public static func every(of step: Step, length: Int) -> Int? {
        switch step.on {
        case .all: return 1
        case .weekdays: return nil
        case .nights(let n):
            guard !n.isEmpty else { return nil }
            if n.count == length { return 1 }
            guard length % n.count == 0 else { return nil }
            let gap = length / n.count
            let sorted = n.sorted()
            for i in 1..<max(1, sorted.count) where sorted[i] - sorted[i - 1] != gap { return nil }
            return gap
        }
    }

    /// How a step's schedule reads in plain words.
    public static func describe(_ step: Step, in sp: SlotPlan, slot: Slot = .pm) -> String {
        let word = slot.word
        switch step.on {
        case .all: return slot == .pm ? "Every night" : "Every morning"
        case .weekdays(let days):
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let d = days.sorted()
            if d.count == 7 { return "Every day" }
            if d.isEmpty { return "No days picked" }
            return d.map { names[$0] }.joined(separator: ", ")
        case .nights(let n):
            if n.isEmpty { return "Not scheduled" }
            if let gap = every(of: step, length: sp.length) {
                switch gap {
                case 1: return slot == .pm ? "Every night" : "Every morning"
                case 2: return "Every other \(word)"
                case 3: return "Every 3rd \(word)"
                default: return "Every \(gap)th \(word)"
                }
            }
            return "\(n.count) of every \(sp.length) \(word)s"
        }
    }

    /// Whether a rotation position is rest-only (no actives) in the base plan.
    public static func isRecoveryPosition(_ sp: SlotPlan, pos: Int, products: [String: Product]) -> Bool {
        !positionHasActives(sp, products: products, pos: pos)
    }
}
