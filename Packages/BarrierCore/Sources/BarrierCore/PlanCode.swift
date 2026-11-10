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
        public static let phases = 6
        public static let name = 80
        public static let note = 280
        public static let amount = 120
        public static let how = 200
        public static let clinic = 60
        public static let bodyName = 24
        public static let cue = 40
        public static let waitMin = 120
        public static let courseDays = 730
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
        public var on: StepOn

        public init(product: Int, amount: String? = nil, how: String? = nil, waitMin: Int? = nil, on: StepOn = .all) {
            self.product = product
            self.amount = amount
            self.how = how
            self.waitMin = waitMin
            self.on = on
        }
    }

    public struct Routine: Hashable, Sendable {
        public var length: Int
        public var steps: [Line]
        /// Evening only. Starts on day 1.
        public var easeIn: [EaseInPhase]
        /// Body routine only: what it's for ("Back"). Required there.
        public var name: String?
        /// Body routine only: a moment ("After shower").
        public var cue: String?

        public init(length: Int = 1, steps: [Line], easeIn: [EaseInPhase] = [], name: String? = nil, cue: String? = nil) {
            self.length = length
            self.steps = steps
            self.easeIn = easeIn
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

    /// The routines this code carries, morning first.
    public var slots: [Slot] { Slot.allCases.filter { routines[$0] != nil } }

    // MARK: Rules

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
            var rotatingActive = false
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
                if out.products[line.product].kind.isActive {
                    if case .weekdays = on {} else { rotatingActive = true }
                }
                return Line(product: line.product,
                            amount: try Self.text(line.amount, max: Limit.amount, "\(step): the amount"),
                            how: try Self.text(line.how, max: Limit.how, "\(step): the how-to", multiline: true),
                            waitMin: line.waitMin, on: on)
            }

            if !r.easeIn.isEmpty {
                guard slot == .pm else { throw PlanCodeError.invalid("\(what): only the evening eases in") }
                guard rotatingActive else { throw PlanCodeError.invalid("\(what): easing in needs a retinoid, exfoliant or treatment") }
                guard r.easeIn.count <= Limit.phases else { throw PlanCodeError.invalid("\(what): at most \(Limit.phases) ease-in phases") }
                for p in r.easeIn {
                    // The same ranges as the editor, so a loaded plan can always be edited.
                    guard p.days % 7 == 0, (7...56).contains(p.days), (0...6).contains(p.extraRest) else {
                        throw PlanCodeError.invalid("\(what): an ease-in phase is 1 to 8 whole weeks with 0 to 6 extra recovery nights")
                    }
                }
            }

            var name: String?
            var cue: String?
            if slot == .body {
                name = try Self.text(r.name, max: Limit.bodyName, "the body routine's name")
                guard name != nil else { throw PlanCodeError.invalid("the body routine needs a name") }
                cue = try Self.text(r.cue, max: Limit.cue, "the body routine's cue")
                bodyUse.formUnion(seen)
            } else {
                guard r.name == nil, r.cue == nil else { throw PlanCodeError.invalid("\(what): only the body routine has a name or a cue") }
                faceUse.formUnion(seen)
            }
            // A rotation no step uses is the same routine every time.
            out.routines[slot] = Routine(length: usesNights ? r.length : 1, steps: steps, easeIn: r.easeIn, name: name, cue: cue)
        }

        guard faceUse.union(bodyUse).count == out.products.count else { throw PlanCodeError.invalid("a product isn't used by any step") }
        // The body routine keeps its own products, as in the editor.
        guard faceUse.isDisjoint(with: bodyUse) else { throw PlanCodeError.invalid("a product is in both a face and the body routine") }
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
        }

        struct R: Codable {
            var l: Int?
            var s: [S]
            var e: [[Int]]?
            var n: String?
            var q: String?
        }

        var v: Int
        var c: String?
        var p: [P]
        var am: R?
        var pm: R?
        var body: R?
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
                return s
            }
            return Wire.R(l: r.length == 1 ? nil : r.length, s: steps,
                          e: r.easeIn.isEmpty ? nil : r.easeIn.map { [$0.days, $0.extraRest] }, n: r.name, q: r.cue)
        }
        return Wire(v: Self.version, c: clinic,
                    p: products.map { Wire.P(n: $0.name, k: $0.kind.rawValue, o: $0.note, d: $0.courseDays) },
                    am: routine(.am), pm: routine(.pm), body: routine(.body), i: ifIrritated)
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
        (["v", "c", "p", "am", "pm", "body", "i"], ["n", "k", "o", "d"], ["l", "s", "e", "n", "q"], ["p", "a", "h", "w", "n", "d"])

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
        for slot in Slot.allCases {
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
        for (slot, r) in [(Slot.am, wire.am), (.pm, wire.pm), (.body, wire.body)] {
            guard let r else { continue }
            let steps: [Line] = try r.s.map { s in
                let on: StepOn
                switch (s.n, s.d) {
                case (nil, nil): on = .all
                case (let n?, nil): on = .nights(n)
                case (nil, let d?): on = .weekdays(d)
                default: throw PlanCodeError.invalid("a step has both rotation positions and weekdays")
                }
                return Line(product: s.p, amount: s.a, how: s.h, waitMin: s.w, on: on)
            }
            let phases: [EaseInPhase] = try (r.e ?? []).map { pair in
                guard pair.count == 2 else { throw PlanCodeError.invalid("an ease-in phase is [days, extra recovery nights]") }
                return EaseInPhase(days: pair[0], extraRest: pair[1])
            }
            if r.e != nil && phases.isEmpty { throw PlanCodeError.invalid("an empty ease-in") }
            routines[slot] = Routine(length: r.l ?? 1, steps: steps, easeIn: phases, name: r.n, cue: r.q)
        }
        try self.init(clinic: wire.c, products: items, routines: routines, ifIrritated: wire.i)
    }

    /// A code for the routines someone has now: to hand a routine on, and for tests.
    /// Finished courses are left out and an ease-in starts over from day 1.
    public init(_ state: AppState, slots: [Slot] = Slot.allCases, clinic: String? = nil, today: Day) throws {
        let byID = Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [Item] = []
        var index: [String: Int] = [:]
        var routines: [Slot: Routine] = [:]
        for slot in Slot.allCases where slots.contains(slot) {
            let sp = state.plan[slot]
            guard sp.enabled else { continue }
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
                lines.append(Line(product: i, amount: step.amount, how: step.how, waitMin: step.waitMin.flatMap { $0 > 0 ? $0 : nil }, on: on))
            }
            guard !lines.isEmpty else { continue }
            routines[slot] = Routine(length: length, steps: lines, easeIn: sp.easeIn?.phases ?? [],
                                     name: slot == .body ? sp.displayName : nil, cue: slot == .body ? sp.cue : nil)
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
        let bodyIDs = Set(plan.body.steps.map(\.productId))
        var pool = products
        var ids = [String?](repeating: nil, count: code.products.count)
        func usedIn(_ i: Int) -> [Slot] { slots.filter { code.routines[$0]?.steps.contains { $0.product == i } == true } }
        let passes: [(Product, PlanCode.Item) -> Bool] = [
            { PlanHistory.norm($0.name) == PlanHistory.norm($1.name) },
            { $0.kind == $1.kind && PlanHistory.base($0.name) == PlanHistory.base($1.name) },
        ]
        for same in passes {
            for (i, item) in code.products.enumerated() where ids[i] == nil {
                let forBody = usedIn(i).contains(.body)
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

        for slot in slots {
            guard let r = code.routines[slot], let start = day1[slot] else { continue }
            var sp = s.plan[slot]
            // A step for the same product keeps its id, so loading the same code twice changes nothing.
            let stepIDs = Dictionary(sp.steps.map { ($0.productId, $0.id) }, uniquingKeysWith: { a, _ in a })
            sp.enabled = true
            sp.length = r.length
            sp.steps = r.steps.map { line in
                let pid = ids[line.product] ?? ""
                return Step(id: stepIDs[pid] ?? makeID(), productId: pid, amount: line.amount, how: line.how, waitMin: line.waitMin, on: line.on)
            }
            sp.names = nil
            sp.easeIn = r.easeIn.isEmpty ? nil : EaseIn(start: start, phases: r.easeIn)
            sp.anchor = Anchor(day: start, pos: 0)
            if slot == .body {
                sp.name = r.name
                sp.cue = r.cue
            }
            s.plan[slot] = sp
        }
        if let text = code.ifIrritated { s.plan.ifIrritated = text }
        s.pruneOrphanProducts()
        return s
    }
}

// MARK: - In words, to check against the clinic's sheet

public struct PlanCodeSummary: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var kind: ProductKind
        /// "Every other night · Pea-size", "On dry skin", "Then wait 20 minutes", "For 12 weeks, until Feb 2".
        public var lines: [String]
        /// The prescriber's own words about this product.
        public var note: String?
    }

    public struct Section: Hashable, Sendable, Identifiable {
        public var slot: Slot
        /// "Evening", "Morning", "Back".
        public var title: String
        /// "Repeats every 4 nights", or nil when it's the same every time.
        public var rotation: String?
        public var rows: [Row]
        /// "Weeks 1–2: actives every 3rd night", … Empty without an ease-in.
        public var easeIn: [String]
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

    /// "Weeks 1–2: actives every 3rd night", ending with when the full routine starts.
    static func easeInLines(_ phases: [EaseInPhase], length: Int) -> [String] {
        var out: [String] = []
        var week = 1
        for p in phases {
            let weeks = max(1, p.days / 7)
            let span = weeks == 1 ? "Week \(week)" : "Weeks \(week)–\(week + weeks - 1)"
            let what: String
            if length == 1 {
                switch p.extraRest {
                case 0: what = "actives every night"
                case 1: what = "actives every other night"
                case 2: what = "actives every 3rd night"
                default: what = "actives every \(p.extraRest + 1)th night"
                }
            } else {
                what = p.extraRest == 0 ? "the normal rotation" : "\(p.extraRest) extra recovery night\(p.extraRest == 1 ? "" : "s") in each cycle"
            }
            out.append("\(span): \(what)")
            week += weeks
        }
        if !out.isEmpty { out.append("From week \(week): the full routine") }
        return out
    }

    /// The code in plain words, as it would load into this state today.
    func summary(for state: AppState, today: Day) -> PlanCodeSummary {
        let after = state.loading(self, today: today)
        let byID = Dictionary(after.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sections: [PlanCodeSummary.Section] = slots.compactMap { slot in
            guard let r = routines[slot] else { return nil }
            let sp = after.plan[slot]
            let rows: [PlanCodeSummary.Row] = sp.steps.enumerated().compactMap { i, step in
                guard let p = byID[step.productId], r.steps.indices.contains(i) else { return nil }
                var first = Engine.describe(step, in: sp, slot: slot)
                if let a = step.amount { first += " · \(a)" }
                var lines = [first]
                if let how = step.how { lines.append(how) }
                if let w = step.waitMin { lines.append("Then wait \(w) minute\(w == 1 ? "" : "s")") }
                if let days = products[r.steps[i].product].courseDays, let until = p.until {
                    lines.append("For \(Self.courseText(days)), until \(until.monthDay)")
                }
                return PlanCodeSummary.Row(id: i, name: p.name, kind: p.kind, lines: lines, note: p.note)
            }
            let old = state.plan[slot]
            return PlanCodeSummary.Section(
                slot: slot, title: slot == .body ? sp.displayName : slot.title,
                rotation: sp.length > 1 ? "Repeats every \(sp.length) \(slot.word)s" : nil,
                rows: rows, easeIn: Self.easeInLines(r.easeIn, length: r.length),
                starts: state.loadDay(slot, today: today),
                replaces: state.onboarded && old.enabled && !old.steps.isEmpty)
        }
        return PlanCodeSummary(clinic: clinic, sections: sections, ifIrritated: ifIrritated)
    }
}
