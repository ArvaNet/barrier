import Foundation

// The whole app state is plain Codable data saved as one JSON file. Every
// decoder tolerates missing fields so older saves keep loading after updates.

/// A routine: the face routines morning and evening, plus one body routine
/// (back, chest, body) with its own time.
public enum Slot: String, Codable, CaseIterable, Sendable, Identifiable {
    case am, pm, body
    public var id: String { rawValue }

    /// The unit a rotation counts in: "every other night / morning / day".
    public var word: String {
        switch self {
        case .am: return "morning"
        case .pm: return "night"
        case .body: return "day"
        }
    }

    public var title: String {
        switch self {
        case .am: return "Morning"
        case .pm: return "Evening"
        case .body: return "Body"
        }
    }

    /// Where on the body this routine is applied.
    public var area: Area { self == .body ? .body : .face }
}

/// Face or body, for photos and skin check-ins.
public enum Area: String, Codable, CaseIterable, Sendable, Identifiable {
    case face, body
    public var id: String { rawValue }
}

public enum ProductKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case cleanser, retinoid, exfoliant, treatment, serum, moisturizer, spf, oral, other
    public var id: String { rawValue }

    /// Retinoids, exfoliants and prescription treatments: the things a recovery night drops.
    public var isActive: Bool { self == .retinoid || self == .exfoliant || self == .treatment }

    public var label: String {
        switch self {
        case .cleanser: return "Cleanser"
        case .retinoid: return "Retinoid"
        case .exfoliant: return "Exfoliant"
        case .treatment: return "Treatment"
        case .serum: return "Serum"
        case .moisturizer: return "Moisturizer"
        case .spf: return "Sunscreen"
        case .oral: return "Medication"
        case .other: return "Other"
        }
    }

    /// Where a new step of this kind goes in the order.
    public var order: Int {
        switch self {
        case .oral: return 0
        case .cleanser: return 1
        case .exfoliant: return 2
        case .retinoid, .treatment: return 3
        case .serum: return 4
        case .moisturizer, .other: return 5
        case .spf: return 6
        }
    }
}

public enum Hue: String, Codable, CaseIterable, Sendable {
    case gold, clay, sage, mist, rose, lilac, dawn
}

public struct Product: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: ProductKind
    /// The dermatologist's instruction for this product, in their words.
    public var note: String?
    /// First day of use. Steps for it aren't due before this.
    public var from: Day?
    /// Last day of a course (e.g. a 12-week antibiotic).
    public var until: Day?

    public init(id: String = makeID(), name: String, kind: ProductKind, note: String? = nil, from: Day? = nil, until: Day? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.note = note
        self.from = from
        self.until = until
    }

    /// "Tretinoin 0.025% cream" → "Tretinoin".
    public var shortName: String { Product.shortName(name) }

    public static func shortName(_ name: String) -> String {
        if let r = name.range(of: #"\s*\d+([.,]\d+)?\s*%.*$"#, options: .regularExpression) {
            let s = name[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? name : s
        }
        return name
    }
}

/// Which instances of a slot a step belongs to.
public enum StepOn: Hashable, Sendable, Codable {
    case all
    /// Positions in the base rotation.
    case nights([Int])
    /// 0 = Sunday … 6 = Saturday.
    case weekdays([Int])

    private enum CodingKeys: String, CodingKey { case type, nights, days }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .type) ?? "all" {
        case "nights": self = .nights(try c.decodeIfPresent([Int].self, forKey: .nights) ?? [])
        case "weekdays": self = .weekdays(try c.decodeIfPresent([Int].self, forKey: .days) ?? [])
        default: self = .all
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all: try c.encode("all", forKey: .type)
        case .nights(let n):
            try c.encode("nights", forKey: .type)
            try c.encode(n, forKey: .nights)
        case .weekdays(let d):
            try c.encode("weekdays", forKey: .type)
            try c.encode(d, forKey: .days)
        }
    }
}

public struct Step: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var productId: String
    public var amount: String?
    public var how: String?
    /// Minutes to wait after this step before the next one.
    public var waitMin: Int?
    public var on: StepOn
    /// Starting this product slowly (see BuildUp.swift). While it runs, `on` is the current stage.
    public var buildUp: BuildUp?

    public init(id: String = makeID(), productId: String, amount: String? = nil, how: String? = nil, waitMin: Int? = nil, on: StepOn = .all, buildUp: BuildUp? = nil) {
        self.id = id
        self.productId = productId
        self.amount = amount
        self.how = how
        self.waitMin = waitMin
        self.on = on
        self.buildUp = buildUp
    }
}

public struct EaseInPhase: Codable, Hashable, Sendable {
    public var days: Int
    /// Extra recovery nights appended to the rotation during this phase.
    public var extraRest: Int

    public init(days: Int, extraRest: Int) {
        self.days = days
        self.extraRest = extraRest
    }
}

public struct EaseIn: Codable, Hashable, Sendable {
    public var start: Day
    public var phases: [EaseInPhase]

    public init(start: Day, phases: [EaseInPhase]) {
        self.start = start
        self.phases = phases
    }

    public var totalDays: Int { phases.reduce(0) { $0 + $1.days } }
}

public struct Anchor: Codable, Hashable, Sendable {
    /// History replay starts here: on `day`, the rotation is at `pos`.
    public var day: Day
    public var pos: Int

    public init(day: Day, pos: Int) {
        self.day = day
        self.pos = pos
    }
}

public struct SlotPlan: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var time: ClockTime
    /// Base rotation length (1 = same every time, 4 = skin cycling).
    public var length: Int
    public var steps: [Step]
    /// Optional custom names per base position ("0": "Tret night").
    public var names: [String: String]?
    public var easeIn: EaseIn?
    public var anchor: Anchor
    /// Body routine only: what it's for ("Back").
    public var name: String?
    /// Body routine only: a moment instead of a clock time ("After shower").
    /// The reminder still uses `time` as the usual moment.
    public var cue: String?

    public init(enabled: Bool = true, time: ClockTime, length: Int = 1, steps: [Step] = [], names: [String: String]? = nil, easeIn: EaseIn? = nil, anchor: Anchor, name: String? = nil, cue: String? = nil) {
        self.enabled = enabled
        self.time = time
        self.length = length
        self.steps = steps
        self.names = names
        self.easeIn = easeIn
        self.anchor = anchor
        self.name = name
        self.cue = cue
    }

    /// "Back", or "Body" when unnamed.
    public var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Body" : n
    }
}

public struct FollowUp: Codable, Hashable, Sendable {
    public var day: Day
    public var with: String?

    public init(day: Day, with: String? = nil) {
        self.day = day
        self.with = with
    }
}

public struct Plan: Codable, Hashable, Sendable {
    public var am: SlotPlan
    public var pm: SlotPlan
    /// Back, chest or body treatment. Off until set up.
    public var body: SlotPlan
    public var followUp: FollowUp?
    /// What the dermatologist said to do if skin gets irritated.
    public var ifIrritated: String?
    public var dermNotes: String?
    public var createdAt: Day

    public init(am: SlotPlan, pm: SlotPlan, body: SlotPlan? = nil, followUp: FollowUp? = nil, ifIrritated: String? = nil, dermNotes: String? = nil, createdAt: Day) {
        self.am = am
        self.pm = pm
        self.body = body ?? Plan.defaultBody(createdAt)
        self.followUp = followUp
        self.ifIrritated = ifIrritated
        self.dermNotes = dermNotes
        self.createdAt = createdAt
    }

    public static func defaultBody(_ day: Day) -> SlotPlan {
        SlotPlan(enabled: false, time: ClockTime(20, 30), length: 1, steps: [], anchor: Anchor(day: day, pos: 0), name: "Back")
    }

    private enum CodingKeys: String, CodingKey {
        case am, pm, body, followUp, ifIrritated, dermNotes, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        am = try c.decode(SlotPlan.self, forKey: .am)
        pm = try c.decode(SlotPlan.self, forKey: .pm)
        createdAt = try c.decode(Day.self, forKey: .createdAt)
        // Saves from before the body routine existed have no "body" key.
        body = (try? c.decodeIfPresent(SlotPlan.self, forKey: .body)) ?? Plan.defaultBody(createdAt)
        followUp = try? c.decodeIfPresent(FollowUp.self, forKey: .followUp)
        ifIrritated = try? c.decodeIfPresent(String.self, forKey: .ifIrritated)
        dermNotes = try? c.decodeIfPresent(String.self, forKey: .dermNotes)
    }

    public subscript(slot: Slot) -> SlotPlan {
        get {
            switch slot {
            case .am: return am
            case .pm: return pm
            case .body: return body
            }
        }
        set {
            switch slot {
            case .am: am = newValue
            case .pm: pm = newValue
            case .body: body = newValue
            }
        }
    }

    /// Routines that are on and have at least one step.
    public var activeSlots: [Slot] {
        Slot.allCases.filter { self[$0].enabled && !self[$0].steps.isEmpty }
    }
}

/// open = nothing logged yet (e.g. a recovery night chosen but not done).
public enum EntryStatus: String, Codable, Sendable {
    case done, skipped, open
}

public struct Entry: Codable, Hashable, Sendable {
    public var day: Day
    public var slot: Slot
    public var status: EntryStatus
    /// Turned into a recovery night: actives dropped, rotation holds.
    public var recovery: Bool?
    /// Snapshot, so history still reads right after plan edits.
    public var pos: Int?
    public var label: String?
    public var hue: Hue?
    /// Step ids ticked, for partial routines.
    public var steps: [String]?
    public var at: Date
    /// Logged afterwards (the weeks before Barrier), not on the day.
    public var filledIn: Bool?

    public init(day: Day, slot: Slot, status: EntryStatus, recovery: Bool? = nil, pos: Int? = nil, label: String? = nil, hue: Hue? = nil, steps: [String]? = nil, at: Date = Date()) {
        self.day = day
        self.slot = slot
        self.status = status
        self.recovery = recovery
        self.pos = pos
        self.label = label
        self.hue = hue
        self.steps = steps
        self.at = at
    }
}

public enum Feeling: String, Codable, CaseIterable, Sendable, Identifiable {
    case calm, dry, tight, flaky, red, stinging, breakout
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    /// Signs that point toward a recovery night.
    public var isIrritation: Bool { self == .tight || self == .red || self == .stinging }
}

public struct CheckIn: Codable, Hashable, Sendable {
    public var day: Day
    public var feel: [Feeling]
    public var note: String?
    public var at: Date
    /// nil = face (saves from before body check-ins).
    public var area: Area?

    public init(day: Day, feel: [Feeling], note: String? = nil, at: Date = Date(), area: Area = .face) {
        self.day = day
        self.feel = feel
        self.note = note
        self.at = at
        self.area = area == .face ? nil : area
    }

    public var place: Area { area ?? .face }
}

public enum PauseReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case travel, irritation, procedure, sick, other
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .travel: return "Traveling"
        case .irritation: return "Skin needs a break"
        case .procedure: return "Procedure or treatment"
        case .sick: return "Unwell"
        case .other: return "Something else"
        }
    }
}

public struct Pause: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var from: Day
    /// Inclusive.
    public var to: Day
    public var reason: PauseReason
    /// Only the routines for this area. nil = every routine.
    public var area: Area?
    /// The actives break set by a procedure. It moves with the procedure.
    public var procedureID: String?

    public init(id: String = makeID(), from: Day, to: Day, reason: PauseReason, area: Area? = nil, procedureID: String? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.reason = reason
        self.area = area
        self.procedureID = procedureID
    }

    public func covers(_ day: Day) -> Bool { from <= day && day <= to }

    /// Whether this pause applies to a routine.
    public func applies(to slot: Slot) -> Bool { area == nil || area == slot.area }
}

/// A treatment done at a clinic: subcision, a laser session, a peel.
public struct Procedure: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var day: Day
    /// nil = face.
    public var area: Area?
    /// Where exactly ("Cheeks", "Upper back").
    public var spot: String?
    /// Clinic or doctor.
    public var clinic: String?
    /// Session 2 of 3. nil = a single treatment.
    public var session: Int?
    /// Planned sessions in the series, if known.
    public var sessions: Int?
    /// The clinic's aftercare instructions, in their words.
    public var note: String?
    /// Days without actives before and after, as the clinic said. Both nil = no break.
    public var breakBefore: Int?
    public var breakAfter: Int?
    public var at: Date

    public init(id: String = makeID(), name: String, day: Day, area: Area = .face, spot: String? = nil, clinic: String? = nil,
                session: Int? = nil, sessions: Int? = nil, note: String? = nil, breakBefore: Int? = nil, breakAfter: Int? = nil, at: Date = Date()) {
        self.id = id
        self.name = name
        self.day = day
        self.area = area == .face ? nil : area
        self.spot = spot
        self.clinic = clinic
        self.session = session
        self.sessions = sessions
        self.note = note
        self.breakBefore = breakBefore
        self.breakAfter = breakAfter
        self.at = at
    }

    public var place: Area { area ?? .face }

    /// The actives break, if the clinic asked for one.
    public var breakDays: (from: Day, to: Day)? {
        guard breakBefore != nil || breakAfter != nil else { return nil }
        return (day.adding(-max(0, breakBefore ?? 0)), day.adding(max(0, breakAfter ?? 0)))
    }

    /// "session 2 of 3", "session 2", or nil for a single treatment.
    public var sessionText: String? {
        guard let n = session else { return nil }
        if let total = sessions, total >= n { return "session \(n) of \(total)" }
        return "session \(n)"
    }

    /// "Subcision, session 2 of 3".
    public var title: String {
        sessionText.map { "\(name), \($0)" } ?? name
    }
}

public struct PhotoMeta: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var day: Day
    public var at: Date
    public var note: String?
    /// nil = face (saves from before body photos).
    public var area: Area?

    public init(id: String = makeID(), day: Day, at: Date = Date(), note: String? = nil, area: Area = .face) {
        self.id = id
        self.day = day
        self.at = at
        self.note = note
        self.area = area == .face ? nil : area
    }

    public var place: Area { area ?? .face }
}

/// One-tap "how's your skin overall" (1 Rough … 5 Great), about once a week.
public struct SkinScore: Codable, Hashable, Sendable {
    public var day: Day
    public var value: Int
    /// nil = face.
    public var area: Area?
    public var at: Date

    public init(day: Day, value: Int, area: Area = .face, at: Date = Date()) {
        self.day = day
        self.value = min(5, max(1, value))
        self.area = area == .face ? nil : area
        self.at = at
    }

    public var place: Area { area ?? .face }
}

/// One product in one routine, as it stood on a day (for the change log).
public struct SnapshotItem: Codable, Hashable, Sendable {
    public var slot: Slot
    public var productID: String
    public var name: String
    /// "Every other night".
    public var schedule: String
    public var amount: String?
    /// Last day of a course.
    public var until: Day?
    /// A retinoid, acid, treatment or medication.
    public var active: Bool?
    /// First day of use, when set.
    public var from: Day?
    /// While building up: the schedule it's building up to ("Every night").
    public var goal: String?
}

/// The routine as it stood at the end of a day it was edited.
public struct PlanSnapshot: Codable, Hashable, Sendable {
    public var day: Day
    public var items: [SnapshotItem]
    /// Slots easing in, with the end of the ease-in ("pm": "2026-11-01").
    public var easing: [String: String]
    /// Routine names by slot ("body": "Back").
    public var names: [String: String]
    /// The routines and their products as they were, so those days replay with the plan they had.
    public var plan: Plan?
    public var products: [Product]?
    /// Recorded when an older save first opened, not by an edit: the same day's edits still count.
    public var start: Bool?

    public init(day: Day, items: [SnapshotItem], easing: [String: String] = [:], names: [String: String] = [:],
                plan: Plan? = nil, products: [Product]? = nil, start: Bool? = nil) {
        self.day = day
        self.items = items
        self.easing = easing
        self.names = names
        self.plan = plan
        self.products = products
        self.start = start
    }
}

public struct Question: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var at: Date
    public var answered: Bool

    public init(id: String = makeID(), text: String, at: Date = Date(), answered: Bool = false) {
        self.id = id
        self.text = text
        self.at = at
        self.answered = answered
    }
}

public enum ThemeMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case timeOfDay, system, day, dusk
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .timeOfDay: return "Time of day"
        case .system: return "Match iPhone"
        case .day: return "Day"
        case .dusk: return "Dusk"
        }
    }
}

public struct Settings: Codable, Hashable, Sendable {
    public var theme: ThemeMode = .timeOfDay
    public var remindersOn: Bool = true
    public var nudge: Bool = true
    public var nudgeAfterMin: Int = 45
    public var spfMidday: Bool = false
    public var spfTime: ClockTime = ClockTime(13, 0)
    /// Weekday 0–6 for the weekly photo, -1 = off.
    public var photoDay: Int = 0
    public var haptics: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case theme, remindersOn, nudge, nudgeAfterMin, spfMidday, spfTime, photoDay, haptics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        theme = (try? c.decodeIfPresent(ThemeMode.self, forKey: .theme)) ?? d.theme
        remindersOn = (try? c.decodeIfPresent(Bool.self, forKey: .remindersOn)) ?? d.remindersOn
        nudge = (try? c.decodeIfPresent(Bool.self, forKey: .nudge)) ?? d.nudge
        nudgeAfterMin = (try? c.decodeIfPresent(Int.self, forKey: .nudgeAfterMin)) ?? d.nudgeAfterMin
        spfMidday = (try? c.decodeIfPresent(Bool.self, forKey: .spfMidday)) ?? d.spfMidday
        spfTime = (try? c.decodeIfPresent(ClockTime.self, forKey: .spfTime)) ?? d.spfTime
        photoDay = (try? c.decodeIfPresent(Int.self, forKey: .photoDay)) ?? d.photoDay
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? d.haptics
    }
}

public struct AppState: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var onboarded: Bool = false
    public var plan: Plan
    public var products: [Product] = []
    public var log: [Entry] = []
    public var checkins: [CheckIn] = []
    public var pauses: [Pause] = []
    public var photos: [PhotoMeta] = []
    public var procedures: [Procedure] = []
    public var scores: [SkinScore] = []
    /// The routine at the end of each day it changed, oldest first (see History.swift).
    public var history: [PlanSnapshot] = []
    public var questions: [Question] = []
    public var settings: Settings = Settings()
    /// One-off cards and notes the user hid.
    public var dismissed: [String] = []
    public var milestonesSeen: [String] = []

    public init(plan: Plan) {
        self.plan = plan
    }

    private enum CodingKeys: String, CodingKey {
        case version, onboarded, plan, products, log, checkins, pauses, photos, procedures, scores, history, questions, settings, dismissed, milestonesSeen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(Plan.self, forKey: .plan)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? false
        // Element by element: one unreadable entry must never cost the whole history.
        products = c.lossyArray(Product.self, forKey: .products)
        log = c.lossyArray(Entry.self, forKey: .log)
        checkins = c.lossyArray(CheckIn.self, forKey: .checkins)
        pauses = c.lossyArray(Pause.self, forKey: .pauses)
        photos = c.lossyArray(PhotoMeta.self, forKey: .photos)
        procedures = c.lossyArray(Procedure.self, forKey: .procedures)
        scores = c.lossyArray(SkinScore.self, forKey: .scores)
        history = c.lossyArray(PlanSnapshot.self, forKey: .history)
        questions = c.lossyArray(Question.self, forKey: .questions)
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        dismissed = (try? c.decodeIfPresent([String].self, forKey: .dismissed)) ?? []
        milestonesSeen = (try? c.decodeIfPresent([String].self, forKey: .milestonesSeen)) ?? []
    }

    public func product(_ id: String) -> Product? { products.first { $0.id == id } }
}

/// Decodes an element or nothing, so arrays survive one bad element.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        let items = (try? decodeIfPresent([Lossy<T>].self, forKey: key)) ?? nil
        return items?.compactMap { $0.value } ?? []
    }
}

public func makeID() -> String {
    let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return String((0..<12).map { _ in chars[Int.random(in: 0..<chars.count)] })
}

// MARK: JSON

public enum StateCoder {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }

    public static func encode(_ s: AppState) throws -> Data { try encoder().encode(s) }
    public static func decode(_ data: Data) throws -> AppState { try decoder().decode(AppState.self, from: data) }
}
