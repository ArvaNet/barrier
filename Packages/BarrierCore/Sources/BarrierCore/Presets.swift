import Foundation

// Starting points. A preset only saves typing; everything stays editable.

public struct QuickProduct: Hashable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var kind: ProductKind
    public var slot: Slot?
    public var amount: String?
    public var how: String?
    /// Suggested spacing in the evening rotation (1 = nightly).
    public var every: Int?
    public var id: String { key }
}

public enum Presets {
    /// Common things a dermatologist prescribes or recommends.
    public static let quickProducts: [QuickProduct] = [
        .init(key: "cleanser", name: "Gentle cleanser", kind: .cleanser, slot: nil, how: "Lukewarm water, pat dry"),
        .init(key: "tretinoin", name: "Tretinoin", kind: .retinoid, slot: .pm, amount: "Pea-size for the whole face", how: "On completely dry skin", every: 1),
        .init(key: "adapalene", name: "Adapalene", kind: .retinoid, slot: .pm, amount: "Pea-size for the whole face", how: "On completely dry skin", every: 1),
        .init(key: "retinol", name: "Retinol serum", kind: .retinoid, slot: .pm, amount: "Pea-size", how: "On dry skin", every: 2),
        .init(key: "azelaic", name: "Azelaic acid", kind: .treatment, slot: nil, amount: "Thin layer"),
        .init(key: "bpo", name: "Benzoyl peroxide", kind: .treatment, slot: .am, amount: "Thin layer on affected areas"),
        .init(key: "clinda", name: "Clindamycin", kind: .treatment, slot: .am, amount: "Thin layer on affected areas"),
        .init(key: "metro", name: "Metronidazole", kind: .treatment, slot: nil, amount: "Thin layer"),
        .init(key: "ivermectin", name: "Ivermectin cream", kind: .treatment, slot: .pm, amount: "Pea-size per area"),
        .init(key: "exfoliant", name: "Exfoliant (AHA/BHA)", kind: .exfoliant, slot: .pm, amount: "Thin layer", every: 4),
        .init(key: "vitc", name: "Vitamin C serum", kind: .serum, slot: .am, amount: "3–4 drops"),
        .init(key: "niacinamide", name: "Niacinamide serum", kind: .serum, slot: nil, amount: "2–3 drops"),
        .init(key: "moisturizer", name: "Moisturizer", kind: .moisturizer, slot: nil),
        .init(key: "spf", name: "Sunscreen SPF 30+", kind: .spf, slot: .am, how: "Last step of the morning. Broad-spectrum."),
        .init(key: "oral", name: "Oral medication", kind: .oral, slot: .am, how: "As prescribed, with water"),
    ]

    public static func quick(_ key: String) -> QuickProduct? { quickProducts.first { $0.key == key } }

    /// Suggested quick-adds for a slot, minus what's already in it.
    public static func suggestions(for slot: Slot, existing: [Product]) -> [QuickProduct] {
        let names = Set(existing.map { $0.name.lowercased() })
        return quickProducts.filter { q in
            (q.slot == nil || q.slot == slot) && !names.contains(q.name.lowercased())
        }
    }

    public static func emptySlot(_ time: ClockTime, today: Day, enabled: Bool = true) -> SlotPlan {
        SlotPlan(enabled: enabled, time: time, length: 1, steps: [], anchor: Anchor(day: today, pos: 0))
    }

    public static func blankState(today: Day) -> AppState {
        AppState(plan: Plan(am: emptySlot(ClockTime(8, 0), today: today), pm: emptySlot(ClockTime(21, 30), today: today), createdAt: today))
    }

    public static func makeProduct(name: String, kind: ProductKind, today: Day) -> Product {
        var p = Product(name: name, kind: kind)
        if kind.isActive || kind == .oral { p.from = today }
        return p
    }

    public static func makeStep(productId: String, from q: QuickProduct?) -> Step {
        Step(productId: productId, amount: q?.amount, how: q?.how, waitMin: nil, on: .all)
    }

    /// Insert a step in a sensible position for its kind.
    public static func insert(_ step: Step, kind: ProductKind, into steps: [Step], kinds: [String: ProductKind]) -> [Step] {
        if let idx = steps.firstIndex(where: { (kinds[$0.productId] ?? .other).order > kind.order }) {
            var s = steps
            s.insert(step, at: idx)
            return s
        }
        return steps + [step]
    }

    /// Weeks 1–2: every 3rd night. Weeks 3–4: every other night. Then the full plan.
    /// A common starting pattern, not a rule: the editor lets you change it.
    public static let easeInPhases: [EaseInPhase] = [
        EaseInPhase(days: 14, extraRest: 2),
        EaseInPhase(days: 14, extraRest: 1),
    ]

    public enum Template: String, CaseIterable, Identifiable, Sendable {
        case derm, retinoid, simple, cycling
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .derm: return "My dermatologist’s routine"
            case .retinoid: return "Starting a retinoid"
            case .simple: return "Just the basics"
            case .cycling: return "Skin cycling"
            }
        }

        public var subtitle: String {
            switch self {
            case .derm: return "Start empty and add what you were given."
            case .retinoid: return "Tretinoin or adapalene, easing in. Set the weeks to your plan."
            case .simple: return "Cleanse, moisturize, sunscreen."
            case .cycling: return "Popular 4-night routine. Not for prescription plans."
            }
        }
    }

    /// Products + plan for a template, keeping times, settings and history.
    public static func apply(_ template: Template, to state: AppState, today: Day) -> AppState {
        var s = state
        var products: [Product] = []
        func add(_ key: String) -> (Product, QuickProduct) {
            let q = quick(key)!
            let p = makeProduct(name: q.name, kind: q.kind, today: today)
            products.append(p)
            return (p, q)
        }
        var am = emptySlot(state.plan.am.time, today: today)
        var pm = emptySlot(state.plan.pm.time, today: today)

        if template != .derm {
            let cleanser = add("cleanser")
            let moist = add("moisturizer")
            let spf = add("spf")
            am.steps = [makeStep(productId: cleanser.0.id, from: cleanser.1), makeStep(productId: moist.0.id, from: moist.1), makeStep(productId: spf.0.id, from: spf.1)]
            switch template {
            case .simple:
                pm.steps = [makeStep(productId: cleanser.0.id, from: cleanser.1), makeStep(productId: moist.0.id, from: moist.1)]
            case .retinoid:
                let ret = add("tretinoin")
                var c = makeStep(productId: cleanser.0.id, from: cleanser.1)
                c.waitMin = 20
                pm.steps = [c, makeStep(productId: ret.0.id, from: ret.1), makeStep(productId: moist.0.id, from: moist.1)]
                pm.easeIn = EaseIn(start: today, phases: easeInPhases)
            case .cycling:
                let ex = add("exfoliant")
                let ret = add("retinol")
                pm.length = 4
                var exStep = makeStep(productId: ex.0.id, from: ex.1)
                exStep.on = .nights([0])
                var retStep = makeStep(productId: ret.0.id, from: ret.1)
                retStep.on = .nights([1])
                pm.steps = [makeStep(productId: cleanser.0.id, from: cleanser.1), exStep, retStep, makeStep(productId: moist.0.id, from: moist.1)]
            case .derm:
                break
            }
        }
        s.products = products
        s.plan.am = am
        s.plan.pm = pm
        s.plan.createdAt = today
        return s
    }

    /// A believable few weeks of history, for screenshots and previews.
    public static func demoState(today: Day) -> AppState {
        let start = today.adding(-23)
        var s = apply(.retinoid, to: blankState(today: start), today: start)
        // A real-looking derm plan: tretinoin easing in + azelaic acid mornings.
        let aze = makeProduct(name: "Azelaic acid 15%", kind: .treatment, today: start)
        s.products.append(aze)
        var azeStep = makeStep(productId: aze.id, from: quick("azelaic"))
        azeStep.on = .all
        let kinds = Dictionary(s.products.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        s.plan.am.steps = insert(azeStep, kind: .treatment, into: s.plan.am.steps, kinds: kinds)
        s.plan.followUp = FollowUp(day: today.adding(19), with: "Dr. Petrauskienė")
        s.plan.ifIrritated = "Skip tretinoin for 2 nights, moisturizer only, then restart every other night."
        s.onboarded = true
        for i in 0..<23 {
            let d = start.adding(i)
            if i == 9 || i == 16 { continue } // two forgotten nights
            let inst = Engine.instance(s, slot: .pm, on: d, today: today)
            s.log.append(Entry(day: d, slot: .pm, status: .done, pos: inst.pos, label: inst.label, hue: inst.hue, at: d.date().addingTimeInterval(22 * 3600)))
            if i % 3 != 1 {
                s.log.append(Entry(day: d, slot: .am, status: .done, label: "Morning routine", hue: .dawn, at: d.date().addingTimeInterval(8 * 3600)))
            }
        }
        s.log.append(Entry(day: today, slot: .am, status: .done, label: "Morning routine", hue: .dawn))
        s.checkins = [
            CheckIn(day: start.adding(4), feel: [.dry, .flaky]),
            CheckIn(day: start.adding(8), feel: [.red, .stinging], note: "Burned a bit around the nose"),
            CheckIn(day: start.adding(13), feel: [.dry]),
            CheckIn(day: start.adding(19), feel: [.calm]),
            CheckIn(day: start.adding(22), feel: [.calm, .breakout], note: "Two small spots on the chin"),
        ]
        s.questions = [
            Question(text: "Can I add vitamin C in the morning?"),
            Question(text: "Is the dryness around my nose normal?"),
        ]
        return s
    }
}
