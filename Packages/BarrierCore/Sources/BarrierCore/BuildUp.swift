import Foundation

// Starting a product slowly, the way dermatologists prescribe retinoids: every 3rd
// night for two weeks, then every other night, then the goal ("every night").
//
// Each stage is a plain schedule on the step (`Step.on`), so the rotation, skipped
// nights, recovery nights and the history all work as for any other step. Moving up
// is the user's call ("if your skin is OK"), so Tendwell asks when a stage's weeks
// are up and never moves on its own. Every move is dated, for the report.

public struct BuildStage: Codable, Hashable, Sendable {
    /// 2 = every other night, 3 = every 3rd night.
    public var every: Int
    /// How long before Tendwell asks about moving up.
    public var days: Int

    public init(every: Int, days: Int) {
        self.every = max(2, every)
        self.days = max(1, days)
    }
}

public struct BuildUp: Codable, Hashable, Sendable {
    public var start: Day
    /// The stages before the goal, slowest first.
    public var stages: [BuildStage]
    /// The day each later stage began. One move per stage means the goal is reached.
    public var moves: [Day]
    /// What it builds up to: 1 = every night, 2 = every other night.
    public var goal: Int

    public init(start: Day, stages: [BuildStage], moves: [Day] = [], goal: Int = 1) {
        self.start = start
        self.stages = stages
        self.moves = moves
        self.goal = max(1, goal)
    }

    /// The stage now: an index into `stages`, or `stages.count` at the goal.
    public var stage: Int { min(moves.count, stages.count) }
    public var done: Bool { moves.count >= stages.count }
    public var current: BuildStage? { done ? nil : stages[stage] }
    /// The schedule now: the current stage, or the goal.
    public var every: Int { current?.every ?? goal }

    public func stageStart(_ i: Int) -> Day { i <= 0 ? start : moves[min(i, moves.count) - 1] }

    /// The day Tendwell asks about moving up, while a stage runs.
    public var checkDay: Day? { current.map { stageStart(stage).adding($0.days) } }

    /// When the goal is reached if every stage goes to plan (or the day it was).
    public var plannedEnd: Day {
        if done { return moves.last ?? start }
        var d = stageStart(stage)
        for s in stages[stage...] { d = d.adding(s.days) }
        return d
    }

    /// The day the goal was reached, if it was.
    public var finished: Day? { done ? (moves.last ?? start) : nil }
}

public extension Presets {
    /// Two weeks every 3rd night, two weeks every other night, then the goal.
    /// A common start for a retinoid, not a rule: every stage is editable.
    static let buildUpStages: [BuildStage] = [
        BuildStage(every: 3, days: 14),
        BuildStage(every: 2, days: 14),
    ]
}

public extension Engine {
    /// "Every night", "Every other night", "Every 3rd night".
    static func everyPhrase(_ n: Int, word: String = "night") -> String {
        switch n {
        case ...1: return "Every \(word)"
        case 2: return "Every other \(word)"
        case 3: return "Every 3rd \(word)"
        default: return "Every \(n)th \(word)"
        }
    }

    /// Roughly how often that is in a week: "2–3× a week".
    static func perWeek(_ n: Int) -> String {
        switch n {
        case ...1: return "7× a week"
        case 2: return "3–4× a week"
        case 3: return "2–3× a week"
        case 4: return "about twice a week"
        default: return "about once a week"
        }
    }

    /// The shortest rotation that keeps every step's pattern (a 6-night rotation
    /// where everything repeats every 2 becomes 2 nights).
    static func compact(_ sp: SlotPlan) -> SlotPlan {
        let L = max(1, sp.length)
        guard L > 1 else { return sp }
        for d in 1..<L where L % d == 0 {
            let fits = sp.steps.allSatisfy { s in
                guard case .nights(let n) = s.on else { return true }
                let set = Set(n)
                return (0..<L).allSatisfy { set.contains($0) == set.contains($0 % d) }
            }
            guard fits else { continue }
            var plan = sp
            plan.steps = sp.steps.map { s in
                guard case .nights(let n) = s.on else { return s }
                var c = s
                c.on = .nights(n.filter { $0 < d }.sorted())
                return c
            }
            plan.length = d
            plan.names = nil
            return plan
        }
        return sp
    }
}

/// Tendwell asking whether to move a product up a stage.
public struct MoveUpAsk: Hashable, Sendable, Identifiable {
    public var slot: Slot
    public var stepID: String
    public var product: Product
    /// The schedule now and the next one (2 = every other night).
    public var from: Int
    public var to: Int
    /// Whole weeks on the current stage.
    public var weeks: Int
    public var id: String { "\(slot.rawValue)-\(stepID)-\(from)" }
}

public enum BuildUps {
    /// Products whose stage is up: Tendwell asks before moving them on.
    public static func asks(_ s: AppState, today: Day) -> [MoveUpAsk] {
        var out: [MoveUpAsk] = []
        for slot in Slot.allCases where s.plan[slot].enabled {
            for step in s.plan[slot].steps {
                guard let b = step.buildUp, let check = b.checkDay, check <= today, let p = s.product(step.productId) else { continue }
                let next = b.stage + 1 < b.stages.count ? b.stages[b.stage + 1].every : b.goal
                let weeks = max(1, b.stageStart(b.stage).days(to: today) / 7)
                out.append(MoveUpAsk(slot: slot, stepID: step.id, product: p, from: b.every, to: next, weeks: weeks))
            }
        }
        return out
    }

    /// The products building up in a routine now.
    public static func running(_ sp: SlotPlan) -> [Step] {
        sp.steps.filter { $0.buildUp.map { !$0.done } ?? false }
    }
}

public extension AppState {
    /// The last day a step was put on (done, and due that day), before `day`.
    func lastApplied(_ slot: Slot, stepID: String, before day: Day, today: Day, lookback: Int = 21) -> Day? {
        let from = day.adding(-lookback)
        let tl = Engine.timeline(self, slot: slot, from: from, to: day.adding(-1), today: today)
        for inst in tl.reversed() {
            guard inst.status == .done, let e = inst.entry else { continue }
            if let ticked = e.steps {
                if ticked.contains(stepID) { return inst.day }
                continue
            }
            if inst.steps.contains(where: { $0.step.id == stepID }) { return inst.day }
            // Before the replay starts, only the logged night's colour says it had actives.
            if inst.steps.isEmpty, e.recovery != true, [.clay, .gold, .rose].contains(e.hue ?? .sage) { return inst.day }
        }
        return nil
    }

    /// Put a step on "every `n`" and line it up so the next one comes `wait` nights
    /// after tonight (0 = tonight). Other steps keep their pattern. Tonight stays tonight.
    /// False when the pattern can't fit the rotation.
    @discardableResult
    mutating func lineUp(_ slot: Slot, stepID: String, every n: Int, wait: Int, today: Day) -> Bool {
        guard let i = plan[slot].steps.firstIndex(where: { $0.id == stepID }) else { return false }
        let tonight = Engine.instance(self, slot: slot, on: today, today: today)
        var sp = plan[slot]
        sp.steps[i].on = .all
        sp = Engine.compact(sp)
        let products = Dictionary(self.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard var next = Engine.setEvery(sp, stepID: stepID, n: n, products: products) else { return false }
        let L = max(1, next.length)
        let keep = max(0, min(tonight.pos, L - 1))
        if n > 1 {
            let offset = (keep + max(0, wait)) % n
            next.steps[i].on = .nights(Array(stride(from: offset, to: L, by: n)))
        }
        next.anchor = Anchor(day: today, pos: keep)
        plan[slot] = next
        return true
    }

    /// Nights to wait before a step is due on "every `n`", from when it was last put on.
    func waitFor(_ slot: Slot, stepID: String, every n: Int, today: Day) -> Int {
        guard n > 1, let last = lastApplied(slot, stepID: stepID, before: today.adding(1), today: today) else { return 0 }
        return max(0, n - last.days(to: today))
    }

    /// Start a step slowly. Its schedule now becomes the goal. False if the first stage can't fit.
    @discardableResult
    mutating func startBuildUp(_ slot: Slot, stepID: String, stages: [BuildStage], start: Day, today: Day) -> Bool {
        guard let i = plan[slot].steps.firstIndex(where: { $0.id == stepID }), let first = stages.first else { return false }
        let step = plan[slot].steps[i]
        let goal = Engine.every(of: step, length: plan[slot].length) ?? 1
        let wait = waitFor(slot, stepID: stepID, every: first.every, today: today)
        var trial = self
        guard trial.lineUp(slot, stepID: stepID, every: first.every, wait: wait, today: today) else { return false }
        trial.plan[slot].steps[i].buildUp = BuildUp(start: start, stages: stages, goal: goal)
        self = trial
        return true
    }

    /// Move a product up a stage (or to its goal), from tonight.
    @discardableResult
    mutating func moveUp(_ slot: Slot, stepID: String, today: Day) -> Bool {
        guard let i = plan[slot].steps.firstIndex(where: { $0.id == stepID }), var b = plan[slot].steps[i].buildUp, !b.done else { return false }
        b.moves.append(today)
        let n = b.every
        let wait = waitFor(slot, stepID: stepID, every: n, today: today)
        var trial = self
        guard trial.lineUp(slot, stepID: stepID, every: n, wait: wait, today: today) else { return false }
        trial.plan[slot].steps[i].buildUp = b
        self = trial
        return true
    }

    /// Stay on this stage another week before Tendwell asks again.
    mutating func notYet(_ slot: Slot, stepID: String, today: Day, days: Int = 7) {
        guard let i = plan[slot].steps.firstIndex(where: { $0.id == stepID }), var b = plan[slot].steps[i].buildUp, !b.done else { return }
        let s = b.stage
        // From today, so a late answer still gets a full week.
        let elapsed = b.stageStart(s).days(to: today)
        b.stages[s].days = max(b.stages[s].days, elapsed) + days
        plan[slot].steps[i].buildUp = b
    }

    /// Stop building up: the step goes to its goal from tonight.
    mutating func endBuildUp(_ slot: Slot, stepID: String, today: Day) {
        guard let i = plan[slot].steps.firstIndex(where: { $0.id == stepID }), let b = plan[slot].steps[i].buildUp else { return }
        let wait = waitFor(slot, stepID: stepID, every: b.goal, today: today)
        lineUp(slot, stepID: stepID, every: b.goal, wait: wait, today: today)
        plan[slot].steps[i].buildUp = nil
    }

    /// Saves from before per-product build-ups eased in a whole routine at once
    /// ("+2 recovery nights per cycle"). Turn that into a build-up on each treatment,
    /// keeping what tonight is and when each one is next due. True if anything changed.
    @discardableResult
    mutating func migrateEaseIn(today: Day) -> Bool {
        var changed = false
        for slot in Slot.allCases {
            guard let ease = plan[slot].easeIn else { continue }
            changed = true
            let tonightPos = Engine.instance(self, slot: slot, on: today, today: today).pos
            let sp = plan[slot]
            let L = max(1, sp.length)
            let products = Dictionary(self.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // When each treatment is next due under the old ease-in.
            let ahead = Engine.timeline(self, slot: slot, from: today, to: today.adding(40), today: today)
            var builds: [(id: String, b: BuildUp, wait: Int)] = []
            for step in sp.steps {
                guard products[step.productId]?.kind.isActive == true, let k = Engine.every(of: step, length: L) else { continue }
                var stages: [BuildStage] = []
                var ends: [Day] = []
                var d = ease.start
                for ph in ease.phases {
                    d = d.adding(ph.days)
                    let every = Int((Double(k) * Double(L + ph.extraRest) / Double(L)).rounded())
                    guard every > k else { continue }
                    stages.append(BuildStage(every: every, days: ph.days))
                    ends.append(d)
                }
                guard !stages.isEmpty else { continue }
                let moves = ends.filter { $0 <= today }
                let b = BuildUp(start: ease.start, stages: stages, moves: moves, goal: k)
                let firstDue = ahead.first { inst in
                    inst.status != .done && inst.steps.contains { $0.step.id == step.id }
                }
                let wait = firstDue.map { today.days(to: $0.day) } ?? 0
                builds.append((step.id, b, wait))
            }
            plan[slot].easeIn = nil
            // Tonight stays tonight (a recovery position past the base rotation folds back in).
            plan[slot].anchor = Anchor(day: today, pos: max(0, min(tonightPos, L - 1)))
            for item in builds {
                if !item.b.done {
                    lineUp(slot, stepID: item.id, every: item.b.every, wait: item.wait, today: today)
                }
                if let i = plan[slot].steps.firstIndex(where: { $0.id == item.id }) {
                    plan[slot].steps[i].buildUp = item.b
                }
            }
        }
        return changed
    }
}
