import Foundation

// The whole app state is plain Codable data saved as one JSON file. Every
// decoder tolerates missing fields so older saves keep loading after updates.

public enum Slot: String, Codable, CaseIterable, Sendable, Identifiable {
    case am, pm
    public var id: String { rawValue }
    public var word: String { self == .pm ? "night" : "morning" }
    public var title: String { self == .pm ? "Evening" : "Morning" }
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
    public var shortName: String {
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

    public init(id: String = makeID(), productId: String, amount: String? = nil, how: String? = nil, waitMin: Int? = nil, on: StepOn = .all) {
        self.id = id
        self.productId = productId
        self.amount = amount
        self.how = how
        self.waitMin = waitMin
        self.on = on
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

    public init(enabled: Bool = true, time: ClockTime, length: Int = 1, steps: [Step] = [], names: [String: String]? = nil, easeIn: EaseIn? = nil, anchor: Anchor) {
        self.enabled = enabled
        self.time = time
        self.length = length
        self.steps = steps
        self.names = names
        self.easeIn = easeIn
        self.anchor = anchor
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
    public var followUp: FollowUp?
    /// What the dermatologist said to do if skin gets irritated.
    public var ifIrritated: String?
    public var dermNotes: String?
    public var createdAt: Day

    public init(am: SlotPlan, pm: SlotPlan, followUp: FollowUp? = nil, ifIrritated: String? = nil, dermNotes: String? = nil, createdAt: Day) {
        self.am = am
        self.pm = pm
        self.followUp = followUp
        self.ifIrritated = ifIrritated
        self.dermNotes = dermNotes
        self.createdAt = createdAt
    }

    public subscript(slot: Slot) -> SlotPlan {
        get { slot == .am ? am : pm }
        set {
            if slot == .am { am = newValue } else { pm = newValue }
        }
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

    public init(day: Day, feel: [Feeling], note: String? = nil, at: Date = Date()) {
        self.day = day
        self.feel = feel
        self.note = note
        self.at = at
    }
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

    public init(id: String = makeID(), from: Day, to: Day, reason: PauseReason) {
        self.id = id
        self.from = from
        self.to = to
        self.reason = reason
    }
}

public struct PhotoMeta: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var day: Day
    public var at: Date
    public var note: String?

    public init(id: String = makeID(), day: Day, at: Date = Date(), note: String? = nil) {
        self.id = id
        self.day = day
        self.at = at
        self.note = note
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
    public var questions: [Question] = []
    public var settings: Settings = Settings()
    /// One-off cards and notes the user hid.
    public var dismissed: [String] = []
    public var milestonesSeen: [String] = []

    public init(plan: Plan) {
        self.plan = plan
    }

    private enum CodingKeys: String, CodingKey {
        case version, onboarded, plan, products, log, checkins, pauses, photos, questions, settings, dismissed, milestonesSeen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(Plan.self, forKey: .plan)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? false
        products = (try? c.decodeIfPresent([Product].self, forKey: .products)) ?? []
        log = (try? c.decodeIfPresent([Entry].self, forKey: .log)) ?? []
        checkins = (try? c.decodeIfPresent([CheckIn].self, forKey: .checkins)) ?? []
        pauses = (try? c.decodeIfPresent([Pause].self, forKey: .pauses)) ?? []
        photos = (try? c.decodeIfPresent([PhotoMeta].self, forKey: .photos)) ?? []
        questions = (try? c.decodeIfPresent([Question].self, forKey: .questions)) ?? []
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        dismissed = (try? c.decodeIfPresent([String].self, forKey: .dismissed)) ?? []
        milestonesSeen = (try? c.decodeIfPresent([String].self, forKey: .milestonesSeen)) ?? []
    }

    public func product(_ id: String) -> Product? { products.first { $0.id == id } }
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
