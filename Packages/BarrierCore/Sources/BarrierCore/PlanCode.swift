import Foundation

// A routine as a clinic hands it over: a short text that fits in one QR code.
//
// It carries the plan and nothing about the patient: no name, no dates. Day 1
// is the day the patient loads it. The format is strict on purpose. A code that
// breaks any rule is refused whole, because half a prescription is worse than none.
//
//   barrier://plan/<payload>
//   payload = base64url (no padding) of compact UTF-8 JSON. Keys: docs/plan-code.md.

public enum PlanCodeError: Error, Equatable, Sendable {
    /// Some other QR code or link, not a routine code.
    case notACode
    /// Cut off or damaged: it didn't decode.
    case unreadable
    /// Made for a newer version of the format.
    case newer
    /// It read fine but breaks a rule. The text is for logs and tests, not for the patient.
    case invalid(String)
}

public struct PlanCode: Hashable, Sendable {
    public static let version = 1
    public static let linkPrefix = "barrier://plan/"

    public enum Limit {
        /// Characters in the payload. A QR code holds 2,953 bytes at most.
        public static let payload = 2600
        public static let products = 24
        public static let steps = 16
        public static let name = 80
        public static let note = 280
        public static let amount = 120
        public static let how = 200
        public static let clinic = 60
        public static let bodyName = 24
        public static let cue = 40
        public static let waitMin = 120
        public static let courseDays = 730
        // Starting slowly: what the step editor lets a person set (StepEditorSheet.swift,
        // BuildUpSection), so a loaded routine can always be opened and edited there.
        /// Stages before the goal: "Add a slower stage" stops at 4.
        public static let stages = 4
        /// A stage's "every": the menu offers every 2nd, 3rd and 4th.
        public static let stageEvery = 2...4
        /// A stage's length: the menu offers 1 to 8 weeks.
        public static let stageWeeks = 1...8
    }

    public struct Item: Hashable, Sendable {
        public var name: String
        public var kind: ProductKind
        /// The prescriber's instruction for this product, in their words.
        public var note: String?
        /// A course: this many days from day 1, then it stops.
        public var courseDays: Int?

        public init(name: String, kind: ProductKind, note: String? = nil, courseDays: Int? = nil) {
            self.name = name
            self.kind = kind
            self.note = note
            self.courseDays = courseDays
        }
    }

    public struct Line: Hashable, Sendable {
        /// Index into `products`.
        public var product: Int
        public var amount: String?
        public var how: String?
        public var waitMin: Int?
        /// The step's own schedule. With a build-up, the goal it builds up to.
        public var on: StepOn
        /// Starting slowly: the stages before `on`, slowest first, from day 1. Empty = none.
        public var buildUp: [BuildStage]

        public init(product: Int, amount: String? = nil, how: String? = nil, waitMin: Int? = nil, on: StepOn = .all, buildUp: [BuildStage] = []) {
            self.product = product
            self.amount = amount
            self.how = how
            self.waitMin = waitMin
            self.on = on
            self.buildUp = buildUp
        }
    }

    public struct Routine: Hashable, Sendable {
        public var length: Int
        public var steps: [Line]
        /// Body routines only: what it's for ("Back"). Required there.
        public var name: String?
        /// Body routines only: a moment ("After shower").
        public var cue: String?

        public init(length: Int = 1, steps: [Line], name: String? = nil, cue: String? = nil) {
            self.length = length
            self.steps = steps
            self.name = name
            self.cue = cue
        }
    }

    public private(set) var clinic: String?
    public private(set) var products: [Item]
    public private(set) var routines: [Slot: Routine]
    /// What to do if the skin gets irritated, in the prescriber's words.
    public private(set) var ifIrritated: String?

    /// Every rule is checked here, so a `PlanCode` that exists is always safe to load.
    public init(clinic: String? = nil, products: [Item], routines: [Slot: Routine], ifIrritated: String? = nil) throws {
        self.clinic = clinic
        self.products = products
        self.routines = routines
        self.ifIrritated = ifIrritated
        self = try checked()
    }

    /// The routines this code carries, evening first, as everywhere in the app.
    public var slots: [Slot] { Slot.ordered.filter { routines[$0] != nil } }

    // MARK: Rules

    static func stageEveryRule(_ step: String) -> String {
        "\(step): each stage is every 2nd, 3rd or 4th time, and less often than the goal"
    }

    static func stageDaysRule(_ step: String) -> String {
        "\(step): each stage is 1 to 8 whole weeks (7 to 56 days)"
    }

    private func checked() throws -> PlanCode {
        var out = self
        out.clinic = try Self.text(clinic, max: Limit.clinic, "the clinic name")
        out.ifIrritated = try Self.text(ifIrritated, max: Limit.note, "the irritation note", multiline: true)

        guard (1...Limit.products).contains(products.count) else { throw PlanCodeError.invalid("needs 1 to \(Limit.products) products") }
        out.products = try products.enumerated().map { i, p in
            guard let name = try Self.text(p.name, max: Limit.name, "product \(i + 1)'s name") else {
                throw PlanCodeError.invalid("product \(i + 1) has no name")
            }
            if let d = p.courseDays, !(1...Limit.courseDays).contains(d) {
                throw PlanCodeError.invalid("product \(i + 1): a course is 1 to \(Limit.courseDays) days")
            }
            let note = try Self.text(p.note, max: Limit.note, "product \(i + 1)'s note", multiline: true)
            return Item(name: name, kind: p.kind, note: note, courseDays: p.courseDays)
        }

        guard !routines.isEmpty else { throw PlanCodeError.invalid("no routine") }
        var faceUse = Set<Int>()
        var bodyUse = Set<Int>()
        for slot in slots {
            guard let r = routines[slot] else { continue }
            let what = "the \(slot.rawValue) routine"
            guard (1...Engine.maxRotation).contains(r.length) else { throw PlanCodeError.invalid("\(what): a rotation is 1 to \(Engine.maxRotation) long") }
            guard (1...Limit.steps).contains(r.steps.count) else { throw PlanCodeError.invalid("\(what) needs 1 to \(Limit.steps) steps") }

            var seen = Set<Int>()
            var usesNights = false
            let steps: [Line] = try r.steps.enumerated().map { n, line in
                let step = "\(what), step \(n + 1)"
                guard out.products.indices.contains(line.product) else { throw PlanCodeError.invalid("\(step): no such product") }
                guard seen.insert(line.product).inserted else { throw PlanCodeError.invalid("\(step): the product is already in this routine") }
                var on = line.on
                switch line.on {
                case .all:
                    break
                case .nights(let nights):
                    guard !nights.isEmpty, Set(nights).count == nights.count, nights.allSatisfy({ (0..<r.length).contains($0) }) else {
                        throw PlanCodeError.invalid("\(step): bad rotation positions")
                    }
                    // On every position is the same as "every time".
                    on = nights.count == r.length ? .all : .nights(nights.sorted())
                case .weekdays(let days):
                    guard !days.isEmpty, Set(days).count == days.count, days.allSatisfy({ (0...6).contains($0) }) else {
                        throw PlanCodeError.invalid("\(step): bad weekdays")
                    }
                    on = .weekdays(days.sorted())
                }
                if let w = line.waitMin, !(1...Limit.waitMin).contains(w) {
                    throw PlanCodeError.invalid("\(step): a wait is 1 to \(Limit.waitMin) minutes")
                }
                if case .nights = on { usesNights = true }

                // Starting slowly: only what the step editor offers.
                if !line.buildUp.isEmpty {
                    // StepEditorSheet.canBuildUp: treatments only.
                    guard out.products[line.product].kind.isActive else {
                        throw PlanCodeError.invalid("\(step): only a retinoid, exfoliant or treatment starts slowly")
                    }
                    // The goal is the step's own schedule, as startBuildUp reads it: every time or every Nth.
                    guard let goal = Engine.every(of: Step(productId: "", on: on), length: r.length) else {
                        throw PlanCodeError.invalid("\(step): starting slowly needs a goal of every time or every Nth, not weekdays or picked days")
                    }
                    guard line.buildUp.count <= Limit.stages else { throw PlanCodeError.invalid("\(step): a build-up has 1 to \(Limit.stages) stages") }
                    for (k, stage) in line.buildUp.enumerated() {
                        guard Limit.stageEvery.contains(stage.every), stage.every > goal else { throw PlanCodeError.invalid(Self.stageEveryRule(step)) }
                        guard stage.days % 7 == 0, Limit.stageWeeks.contains(stage.days / 7) else { throw PlanCodeError.invalid(Self.stageDaysRule(step)) }
                        if k > 0, stage.every > line.buildUp[k - 1].every {
                            throw PlanCodeError.invalid("\(step): the stages go from the slowest to the fastest")
                        }
                    }
                }
                return Line(product: line.product,
                            amount: try Self.text(line.amount, max: Limit.amount, "\(step): the amount"),
                            how: try Self.text(line.how, max: Limit.how, "\(step): the how-to", multiline: true),
                            waitMin: line.waitMin, on: on, buildUp: line.buildUp)
            }

            var name: String?
            var cue: String?
            if slot.isBody {
                name = try Self.text(r.name, max: Limit.bodyName, "the \(slot.rawValue) routine's name")
                guard name != nil else { throw PlanCodeError.invalid("the \(slot.rawValue) routine needs a name") }
                cue = try Self.text(r.cue, max: Limit.cue, "the \(slot.rawValue) routine's cue")
                bodyUse.formUnion(seen)
            } else {
                guard r.name == nil, r.cue == nil else { throw PlanCodeError.invalid("\(what): only a body routine has a name or a cue") }
                faceUse.formUnion(seen)
            }
            // A rotation no step uses is the same routine every time.
            out.routines[slot] = Routine(length: usesNights ? r.length : 1, steps: steps, name: name, cue: cue)
        }

        guard faceUse.union(bodyUse).count == out.products.count else { throw PlanCodeError.invalid("a product isn't used by any step") }
        // Face and body keep their own products, as in the editor. The two body routines may share.
        guard faceUse.isDisjoint(with: bodyUse) else { throw PlanCodeError.invalid("a product is in both a face and a body routine") }

        // Nothing loads halfway: every build-up is placed here, the way loading places it.
        let day = Day(2026, 1, 1)
        var scratch = Presets.blankState(today: day)
        scratch.products = out.products.map { Product(name: $0.name, kind: $0.kind) }
        let ids = scratch.products.map(\.id)
        for slot in out.slots {
            guard let r = out.routines[slot], r.steps.contains(where: { !$0.buildUp.isEmpty }) else { continue }
            guard scratch.place(r, slot: slot, productIDs: ids, start: day) else {
                throw PlanCodeError.invalid("the \(slot.rawValue) routine: a build-up doesn't fit the rotation")
            }
        }

        guard out.payload.count <= Limit.payload else { throw PlanCodeError.invalid("too much text to fit in one code") }
        return out
    }

    /// Trimmed, or nil when empty. Refuses control characters and text that changes reading direction.
    private static func text(_ s: String?, max: Int, _ what: String, multiline: Bool = false) throws -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        for u in t.unicodeScalars {
            let v = u.value
            let control = v < 0x20 || (0x7F...0x9F).contains(v)
            let direction = (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v)
            if direction || (control && !(multiline && v == 0x0A)) {
                throw PlanCodeError.invalid("\(what) has characters that can't be shown")
            }
        }
        guard t.count <= max else { throw PlanCodeError.invalid("\(what) is longer than \(max) characters") }
        return t
    }

    // MARK: Text form

    private struct Wire: Codable {
        struct P: Codable {
            var n: String
            var k: String
            var o: String?
            var d: Int?
        }

        struct S: Codable {
            var p: Int
            var a: String?
            var h: String?
            var w: Int?
            var n: [Int]?
            var d: [Int]?
            var b: [[Int]]?
        }

        struct R: Codable {
            var l: Int?
            var s: [S]
            var n: String?
            var q: String?
        }

        var v: Int
        var c: String?
        var p: [P]
        var am: R?
        var pm: R?
        var body: R?
        var body2: R?
        var i: String?
    }

    private var wire: Wire {
        func routine(_ slot: Slot) -> Wire.R? {
            guard let r = routines[slot] else { return nil }
            let steps = r.steps.map { line -> Wire.S in
                var s = Wire.S(p: line.product, a: line.amount, h: line.how, w: line.waitMin)
                switch line.on {
                case .all: break
                case .nights(let n): s.n = n
                case .weekdays(let d): s.d = d
                }
                if !line.buildUp.isEmpty { s.b = line.buildUp.map { [$0.every, $0.days] } }
                return s
            }
            return Wire.R(l: r.length == 1 ? nil : r.length, s: steps, n: r.name, q: r.cue)
        }
        return Wire(v: Self.version, c: clinic,
                    p: products.map { Wire.P(n: $0.name, k: $0.kind.rawValue, o: $0.note, d: $0.courseDays) },
                    am: routine(.am), pm: routine(.pm), body: routine(.body), body2: routine(.body2), i: ifIrritated)
    }

    /// The part after `barrier://plan/`.
    public var payload: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? e.encode(wire)) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// What the QR code holds.
    public var link: String { Self.linkPrefix + payload }

    /// Whether a scanned text or an opened link is meant as a routine code at all.
    public static func isLink(_ text: String) -> Bool { payload(in: text) != nil }

    static func payload(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: linkPrefix, options: [.anchored, .caseInsensitive]) { return String(t[r.upperBound...]) }
        // A web link that carries the same code after "#plan/", for sheets whose code also opens a page.
        if t.lowercased().hasPrefix("https://"), let r = t.range(of: "#plan/") { return String(t[r.upperBound...]) }
        return nil
    }

    private static let keys: (code: Set<String>, product: Set<String>, routine: Set<String>, step: Set<String>) =
        (["v", "c", "p", "am", "pm", "body", "body2", "i"], ["n", "k", "o", "d"], ["l", "s", "n", "q"], ["p", "a", "h", "w", "n", "d", "b"])

    /// A key the format doesn't know could be an instruction this version would silently drop.
    private static func only(_ object: Any?, _ allowed: Set<String>, _ what: String) throws {
        guard let object = object as? [String: Any] else { return }
        if let extra = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw PlanCodeError.invalid("\(what) has an unknown key \"\(extra)\"")
        }
    }

    /// Read a scanned code or an opened link.
    public init(link text: String) throws {
        guard let payload = Self.payload(in: text) else { throw PlanCodeError.notACode }
        guard payload.count <= Limit.payload else { throw PlanCodeError.invalid("too long") }
        var b64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard !payload.isEmpty, let data = Data(base64Encoded: b64),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw PlanCodeError.unreadable }

        guard let v = object["v"] as? Int else { throw PlanCodeError.invalid("no version") }
        if v > Self.version { throw PlanCodeError.newer }
        guard v == Self.version else { throw PlanCodeError.invalid("version \(v)") }

        try Self.only(object, Self.keys.code, "the code")
        for p in object["p"] as? [Any] ?? [] { try Self.only(p, Self.keys.product, "a product") }
        for slot in Slot.ordered {
            let r = object[slot.rawValue] as? [String: Any]
            try Self.only(r, Self.keys.routine, "the \(slot.rawValue) routine")
            for s in r?["s"] as? [Any] ?? [] { try Self.only(s, Self.keys.step, "a step") }
        }

        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw PlanCodeError.invalid("wrong shape")
        }

        let items: [Item] = try wire.p.enumerated().map { i, p in
            guard let kind = ProductKind(rawValue: p.k) else { throw PlanCodeError.invalid("product \(i + 1): unknown kind \"\(p.k)\"") }
            return Item(name: p.n, kind: kind, note: p.o, courseDays: p.d)
        }
        var routines: [Slot: Routine] = [:]
        for (slot, r) in [(Slot.pm, wire.pm), (.am, wire.am), (.body, wire.body), (.body2, wire.body2)] {
            guard let r else { continue }
            let steps: [Line] = try r.s.enumerated().map { n, s in
                let step = "the \(slot.rawValue) routine, step \(n + 1)"
                let on: StepOn
                switch (s.n, s.d) {
                case (nil, nil): on = .all
                case (let n?, nil): on = .nights(n)
                case (nil, let d?): on = .weekdays(d)
                default: throw PlanCodeError.invalid("a step has both rotation positions and weekdays")
                }
                // Checked raw here: a BuildStage rounds what it can't hold.
                let stages: [BuildStage] = try (s.b ?? []).map { pair in
                    guard pair.count == 2 else { throw PlanCodeError.invalid("\(step): a stage is [every, days]") }
                    guard Limit.stageEvery.contains(pair[0]) else { throw PlanCodeError.invalid(Self.stageEveryRule(step)) }
                    guard pair[1] >= 7 else { throw PlanCodeError.invalid(Self.stageDaysRule(step)) }
                    return BuildStage(every: pair[0], days: pair[1])
                }
                if s.b != nil && stages.isEmpty { throw PlanCodeError.invalid("\(step): an empty build-up") }
                return Line(product: s.p, amount: s.a, how: s.h, waitMin: s.w, on: on, buildUp: stages)
            }
            routines[slot] = Routine(length: r.l ?? 1, steps: steps, name: r.n, cue: r.q)
        }
        try self.init(clinic: wire.c, products: items, routines: routines, ifIrritated: wire.i)
    }

    /// A code for the routines someone has now, for tests. Finished courses are left out,
    /// and a running build-up starts over from day 1 with all its stages.
    public init(_ state: AppState, slots: [Slot] = Slot.ordered, clinic: String? = nil, today: Day) throws {
        let byID = Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [Item] = []
        var index: [String: Int] = [:]
        var routines: [Slot: Routine] = [:]
        for slot in Slot.ordered where slots.contains(slot) {
            var sp = state.plan[slot]
            guard sp.enabled else { continue }
            // A step building up is written at its goal, with its stages.
            for step in sp.steps {
                guard let b = step.buildUp, !b.done else { continue }
                guard let goal = Engine.setEvery(sp, stepID: step.id, n: b.goal, products: byID) else {
                    throw PlanCodeError.invalid("the \(slot.rawValue) routine: a goal doesn't fit the rotation")
                }
                sp = goal
            }
            let length = max(1, sp.length)
            var lines: [Line] = []
            for step in sp.steps {
                guard let p = byID[step.productId] else { continue }
                if let until = p.until, until < today { continue }
                let i: Int
                if let known = index[p.id] {
                    i = known
                } else {
                    i = items.count
                    index[p.id] = i
                    items.append(Item(name: p.name, kind: p.kind, note: p.note, courseDays: p.until.map { today.days(to: $0) + 1 }))
                }
                var on = step.on
                if case .nights(let n) = on { on = .nights(n.filter { $0 < length }) }
                let stages = step.buildUp.flatMap { $0.done ? nil : $0.stages } ?? []
                lines.append(Line(product: i, amount: step.amount, how: step.how, waitMin: step.waitMin.flatMap { $0 > 0 ? $0 : nil }, on: on, buildUp: stages))
            }
            guard !lines.isEmpty else { continue }
            routines[slot] = Routine(length: length, steps: lines,
                                     name: slot.isBody ? sp.displayName : nil, cue: slot.isBody ? sp.cue : nil)
        }
        try self.init(clinic: clinic, products: items, routines: routines, ifIrritated: state.plan.ifIrritated)
    }
}

// MARK: - Loading a code

public extension AppState {
    /// Day 1 of a loaded routine: today, or tomorrow when today's is already logged
    /// (so the first night of a new rotation is never skipped).
    func loadDay(_ slot: Slot, today: Day) -> Day {
        guard onboarded, plan[slot].enabled, let e = entry(today, slot), e.status != .open else { return today }
        return today.adding(1)
    }

    /// The state after loading a clinic's code. The routines the code carries are
    /// replaced; the others, the log, photos and everything else stay.
    func loading(_ code: PlanCode, today: Day) -> AppState {
        var s = self
        let slots = code.slots
        var day1: [Slot: Day] = [:]
        for slot in slots { day1[slot] = loadDay(slot, today: today) }

        // The patient's own product when it's the same one, so its first day of use stays.
        // Face and body products never mix.
        let bodyIDs = Set(Slot.bodies.flatMap { plan[$0].steps.map(\.productId) })
        var pool = products
        var ids = [String?](repeating: nil, count: code.products.count)
        func usedIn(_ i: Int) -> [Slot] { slots.filter { code.routines[$0]?.steps.contains { $0.product == i } == true } }
        let passes: [(Product, PlanCode.Item) -> Bool] = [
            { PlanHistory.norm($0.name) == PlanHistory.norm($1.name) },
            { $0.kind == $1.kind && PlanHistory.base($0.name) == PlanHistory.base($1.name) },
        ]
        for same in passes {
            for (i, item) in code.products.enumerated() where ids[i] == nil {
                let forBody = usedIn(i).contains { $0.isBody }
                guard let j = pool.firstIndex(where: { bodyIDs.contains($0.id) == forBody && same($0, item) }) else { continue }
                ids[i] = pool.remove(at: j).id
            }
        }

        for (i, item) in code.products.enumerated() {
            let start = usedIn(i).compactMap { day1[$0] }.min() ?? today
            var p = ids[i].flatMap { id in s.products.first { $0.id == id } } ?? Product(name: item.name, kind: item.kind)
            p.name = item.name
            p.kind = item.kind
            p.note = item.note
            if item.kind.isActive || item.kind == .oral {
                p.from = min(p.from ?? start, start)
            }
            p.until = item.courseDays.map { start.adding($0 - 1) }
            s.upsertProduct(p)
            ids[i] = p.id
        }

        let productIDs = ids.map { $0 ?? "" }
        for slot in slots {
            guard let r = code.routines[slot], let start = day1[slot] else { continue }
            // The code's rules placed every build-up already, so this never stops halfway.
            guard s.place(r, slot: slot, productIDs: productIDs, start: start) else { return self }
        }
        if let text = code.ifIrritated { s.plan.ifIrritated = text }
        s.pruneOrphanProducts()
        return s
    }

    /// Put a code's routine in place from day 1: its steps on their own schedules, then each
    /// build-up's first stage, started the way the step editor starts one. False when a
    /// build-up doesn't fit the rotation; the caller then keeps nothing.
    internal mutating func place(_ r: PlanCode.Routine, slot: Slot, productIDs: [String], start: Day) -> Bool {
        var sp = plan[slot]
        // A step for the same product keeps its id, so loading the same code twice changes nothing.
        let stepIDs = Dictionary(sp.steps.map { ($0.productId, $0.id) }, uniquingKeysWith: { a, _ in a })
        sp.enabled = true
        sp.length = r.length
        sp.steps = r.steps.map { line in
            let pid = productIDs.indices.contains(line.product) ? productIDs[line.product] : ""
            return Step(id: stepIDs[pid] ?? makeID(), productId: pid, amount: line.amount, how: line.how, waitMin: line.waitMin, on: line.on)
        }
        sp.names = nil
        sp.easeIn = nil
        sp.anchor = Anchor(day: start, pos: 0)
        if slot.isBody {
            sp.name = r.name
            sp.cue = r.cue
        }
        plan[slot] = sp
        // Day 1 is "tonight" for the build-up: it starts then with no moves, spaced from the
        // last time the patient's own log shows it on (the app's waitFor), and never moves up by itself.
        for (line, step) in zip(r.steps, sp.steps) where !line.buildUp.isEmpty {
            guard startBuildUp(slot, stepID: step.id, stages: line.buildUp, start: start, today: start) else { return false }
        }
        return true
    }
}

// MARK: - In words, to check against the clinic's sheet

public struct PlanCodeSummary: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var kind: ProductKind
        /// "Every 3rd night, building up to every night · Pea-size", "Every 3rd night for 2 weeks,
        /// then every other night for 2 weeks", "On dry skin", "Then wait 20 minutes", "For 12 weeks, until Feb 2".
        public var lines: [String]
        /// The prescriber's own words about this product.
        public var note: String?
    }

    public struct Section: Hashable, Sendable, Identifiable {
        public var slot: Slot
        /// "Evening", "Morning", "Back".
        public var title: String
        /// "Repeats every 4 nights" as the sheet has it, or nil when it's the same every time.
        public var rotation: String?
        public var rows: [Row]
        /// Day 1.
        public var starts: Day
        /// The patient already has this routine: it gets replaced.
        public var replaces: Bool
        public var id: String { slot.rawValue }
    }

    public var clinic: String?
    public var sections: [Section]
    public var ifIrritated: String?
}

public extension PlanCode {
    /// "12 weeks", "10 days".
    static func courseText(_ days: Int) -> String {
        if days % 7 == 0 { return days == 7 ? "1 week" : "\(days / 7) weeks" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// A build-up in the editor's words: "Every 3rd night for 2 weeks, then every other night
    /// for 2 weeks", then that Tendwell asks before each move up.
    static func buildUpLines(_ stages: [BuildStage], word: String) -> [String] {
        guard !stages.isEmpty else { return [] }
        let plan = stages.enumerated().map { i, st in
            let phrase = Engine.everyPhrase(st.every, word: word)
            return "\(i == 0 ? phrase : PlanHistory.lowered(phrase)) for \(courseText(st.days))"
        }
        return [plan.joined(separator: ", then "), "Tendwell asks how your skin is before each move up"]
    }

    /// The code in plain words, as it would load into this state today.
    func summary(for state: AppState, today: Day) -> PlanCodeSummary {
        let after = state.loading(self, today: today)
        let byID = Dictionary(after.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sections: [PlanCodeSummary.Section] = slots.compactMap { slot in
            guard let r = routines[slot] else { return nil }
            let sp = after.plan[slot]
            // The schedules as the sheet has them: a build-up can stretch the loaded rotation.
            var sheet = sp
            sheet.length = r.length
            let rows: [PlanCodeSummary.Row] = sp.steps.enumerated().compactMap { i, step in
                guard let p = byID[step.productId], r.steps.indices.contains(i) else { return nil }
                let line = r.steps[i]
                let goal = Step(productId: step.productId, on: line.on)
                var first = Engine.describe(goal, in: sheet, slot: slot)
                // A build-up as the routine's own row says it: the first stage, building up to the goal.
                if let stage = line.buildUp.first {
                    first = Engine.everyPhrase(stage.every, word: slot.word)
                        + ", building up to \(PlanHistory.lowered(Engine.everyPhrase(Engine.every(of: goal, length: r.length) ?? 1, word: slot.word)))"
                }
                if let a = step.amount { first += " · \(a)" }
                var lines = [first]
                lines += Self.buildUpLines(line.buildUp, word: slot.word)
                if let how = step.how { lines.append(how) }
                if let w = step.waitMin { lines.append("Then wait \(w) minute\(w == 1 ? "" : "s")") }
                if let days = products[line.product].courseDays, let until = p.until {
                    lines.append("For \(Self.courseText(days)), until \(until.monthDay)")
                }
                return PlanCodeSummary.Row(id: i, name: p.name, kind: p.kind, lines: lines, note: p.note)
            }
            let old = state.plan[slot]
            return PlanCodeSummary.Section(
                slot: slot, title: slot.isBody ? after.plan.shortName(slot) : slot.title,
                rotation: r.length > 1 ? "Repeats every \(r.length) \(slot.word)s" : nil,
                rows: rows,
                starts: state.loadDay(slot, today: today),
                replaces: state.onboarded && old.enabled && !old.steps.isEmpty)
        }
        return PlanCodeSummary(clinic: clinic, sections: sections, ifIrritated: ifIrritated)
    }
}
