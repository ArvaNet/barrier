import Foundation

// Filling in the weeks before Barrier: someone who followed the routine on paper says
// since when and which days they missed; every other day counts as done. Tonight stays
// tonight, and the entries are marked as filled in so the report can say so.

public extension AppState {
    /// The earliest day that can be filled in: the report's 14-week window.
    static func fillInEarliest(today: Day) -> Day { today.adding(-97) }

    /// The routines a fill-in covers: on, with steps, and there from the plan's start
    /// (a back routine added later has nothing to fill in before it began).
    func fillInSlots() -> [Slot] {
        // Evening first, as everywhere in the app.
        Slot.ordered.filter { slot in
            let sp = plan[slot]
            return sp.enabled && !sp.steps.isEmpty && (!slot.isBody || sp.anchor.day <= plan.createdAt)
        }
    }

    /// The days a fill-in from `start` would log: up to the day before the plan began.
    func fillInDays(since start: Day) -> [Day] {
        var out: [Day] = []
        var d = start
        while d < plan.createdAt && out.count < 98 {
            out.append(d)
            d = d.adding(1)
        }
        return out
    }

    /// The first and last day that were filled in afterwards, if any.
    var filledInSpan: (from: Day, to: Day)? {
        let days = log.filter { $0.filledIn == true }.map(\.day)
        guard let a = days.min(), let b = days.max() else { return nil }
        return (a, b)
    }

    /// Move the plan's start back to `start` and log every day before the old start:
    /// done, or skipped for the days in `missed`.
    /// `skipped`: days a routine was done without some of its products (product ids), like
    /// a few nights without the retinoid. Those nights log as done with the rest of the steps.
    mutating func fillIn(since start: Day, missed: [Slot: Set<Day>], skipped: [Slot: [Day: Set<String>]] = [:], today: Day, at now: Date = Date()) {
        let oldStart = plan.createdAt
        let start = max(start, Self.fillInEarliest(today: today))
        guard start < oldStart, oldStart <= today else { return }
        let slots = fillInSlots()
        let tonight = Dictionary(uniqueKeysWithValues: slots.map { ($0, Engine.instance(self, slot: $0, on: today, today: today)) })
        // Where the first recorded routine stood when it began (before anything moves).
        let baseAnchors = history.first?.plan.map { p in Dictionary(uniqueKeysWithValues: Slot.allCases.map { ($0, p[$0].anchor) }) } ?? [:]

        // What began with the plan began on the real start: the plan, an ease-in, the
        // treatments. The change log's snapshots move with it, so this isn't a "change".
        plan = Self.moved(plan, from: oldStart, to: start)
        for i in products.indices where products[i].from == oldStart { products[i].from = start }
        for i in history.indices {
            if let p = history[i].plan {
                history[i].plan = Self.moved(p, from: oldStart, to: start)
                for slot in Slot.allCases {
                    if let e = history[i].plan?[slot].easeIn, !e.phases.isEmpty {
                        history[i].easing[slot.rawValue] = e.start.adding(e.totalDays).iso
                    }
                }
            }
            for j in history[i].items.indices where history[i].items[j].from == oldStart { history[i].items[j].from = start }
            if var prods = history[i].products {
                for j in prods.indices where prods[j].from == oldStart { prods[j].from = start }
                history[i].products = prods
            }
        }
        if !history.isEmpty, history[0].day > start { history[0].day = start }

        for slot in slots {
            let fill = { (s: inout AppState) in
                s.logFilledIn(slot, from: start, to: oldStart.adding(-1), missed: missed[slot] ?? [], skipped: skipped[slot] ?? [:], today: today, at: now)
            }
            if plan[slot].anchor.day <= oldStart {
                // The rotation hasn't changed since the start: replay it from the real start
                // and keep the starting position that lands on tonight's night.
                let want = tonight[slot]
                let pick = Self.bestStart(self, slot: slot, start: start, fill: fill) { s in
                    let i = Engine.instance(s, slot: slot, on: today, today: today)
                    return i.pos == want?.pos ? (i.rest == want?.rest ? 2 : 1) : 0
                }
                self = pick.state
                // The first recorded routine is the same rotation: it starts the same way.
                if let a = baseAnchors[slot], a.day <= oldStart, !history.isEmpty {
                    history[0].plan?[slot].anchor = plan[slot].anchor
                }
            } else if let base = history.first?.plan, let target = baseAnchors[slot], target.day <= oldStart {
                // The rotation was edited since: those weeks replay with the routine as it
                // was at the start, landing where that routine stood on its first day.
                var b = self
                b.plan = base
                let pick = Self.bestStart(b, slot: slot, start: start, fill: fill) { s in
                    Engine.instance(s, slot: slot, on: target.day, today: today).pos == target.pos ? 2 : 0
                }
                log = pick.state.log
                history[0].plan?[slot].anchor = pick.anchor
            }
        }
    }

    /// The plan with what started on `old` starting on `new` instead.
    private static func moved(_ p: Plan, from old: Day, to new: Day) -> Plan {
        var p = p
        p.createdAt = new
        for slot in Slot.allCases {
            if p[slot].easeIn?.start == old { p[slot].easeIn?.start = new }
            for i in p[slot].steps.indices where p[slot].steps[i].buildUp?.start == old { p[slot].steps[i].buildUp?.start = new }
            if p[slot].anchor.day == old, !slot.isBody || p[slot].enabled { p[slot].anchor.day = new }
        }
        return p
    }

    /// Try every starting position for the rotation; keep the best-scoring one.
    private static func bestStart(_ s: AppState, slot: Slot, start: Day, fill: (inout AppState) -> Void,
                                  score: (AppState) -> Int) -> (state: AppState, anchor: Anchor) {
        let sp = s.plan[slot]
        let longest = max(1, sp.length) + (sp.easeIn?.phases.map(\.extraRest).max() ?? 0)
        var best: (state: AppState, anchor: Anchor, score: Int)?
        for p0 in 0..<longest {
            var trial = s
            trial.plan[slot].anchor = Anchor(day: start, pos: p0)
            fill(&trial)
            let sc = score(trial)
            if best == nil || sc > best!.score { best = (trial, trial.plan[slot].anchor, sc) }
            if sc == 2 { break }
        }
        return (best!.state, best!.anchor)
    }

    /// Day by day, since each day's place in the rotation depends on the days before it.
    private mutating func logFilledIn(_ slot: Slot, from: Day, to: Day, missed: Set<Day>, skipped: [Day: Set<String>] = [:], today: Day, at: Date) {
        guard from <= to else { return }
        var d = from
        while d <= to {
            if entry(d, slot) == nil {
                let inst = Engine.instance(self, slot: slot, on: d, today: today)
                if !inst.steps.isEmpty && inst.status != .off {
                    // Done, but without the products left out that day: the steps that were put on.
                    let left = skipped[d] ?? []
                    let kept = inst.steps.filter { !left.contains($0.product.id) }.map(\.step.id)
                    let partial = !missed.contains(d) && kept.count < inst.steps.count
                    let status: EntryStatus = missed.contains(d) || (partial && kept.isEmpty) ? .skipped : .done
                    var e = Entry(day: d, slot: slot, status: status,
                                  pos: inst.pos, label: inst.label, hue: inst.hue, steps: partial && !kept.isEmpty ? kept : nil, at: at)
                    e.filledIn = true
                    log.append(e)
                }
            }
            d = d.adding(1)
        }
        log.sort { a, b in a.day == b.day ? a.slot.rawValue < b.slot.rawValue : a.day < b.day }
    }
}


public extension AppState {
    /// For the fill-in calendar: the days a product would have been due, if the weeks
    /// before were followed as marked so far. Empty when the replay can't tell.
    func fillInDue(_ slot: Slot, productID: String, since start: Day, missed: [Slot: Set<Day>], today: Day) -> Set<Day> {
        var trial = self
        trial.fillIn(since: start, missed: missed, today: today)
        var out: Set<Day> = []
        for d in fillInDays(since: start) {
            let e = trial.entry(d, slot)
            let inst = Engine.instance(trial, slot: slot, on: d, today: today)
            if inst.steps.contains(where: { $0.product.id == productID }) { out.insert(d) }
            // Before the replay starts, the night's colour is all there is: treatments wear one.
            else if inst.steps.isEmpty, let h = e?.hue, [.clay, .gold, .rose].contains(h),
                    product(productID)?.kind.isActive == true { out.insert(d) }
        }
        return out
    }
}
