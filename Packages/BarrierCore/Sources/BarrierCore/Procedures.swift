import Foundation

// Procedures done at a clinic: subcision, laser, peels, microneedling,
// injections. Copy follows docs/procedure-facts.md: Barrier records what the
// clinic said and never sets timing itself. The clinic's dates always win.

/// What Today shows about a procedure.
public enum ProcedureMoment: Hashable, Sendable {
    /// Coming up: 0 = today.
    case upcoming(Procedure, inDays: Int)
    /// The first two weeks after.
    case after(Procedure, day: Int)
    /// A few weeks on, with no photo since: time for an "after".
    case photo(Procedure, weeks: Int)

    public var procedure: Procedure {
        switch self {
        case .upcoming(let p, _), .after(let p, _), .photo(let p, _): return p
        }
    }

    /// The id a "hide" tap stores. Upcoming procedures can't be hidden.
    public var dismissID: String? {
        switch self {
        case .upcoming: return nil
        case .after(let p, _): return "proc:\(p.id):after"
        case .photo(let p, let w): return "proc:\(p.id):w\(w)"
        }
    }
}

public enum Procedures {
    /// Quick picks in the add sheet. Anything else can be typed.
    public static let names = [
        "Subcision", "Fractional CO2 laser", "Erbium laser", "Non-ablative laser", "Pico laser",
        "Vascular laser", "IPL", "Microneedling", "RF microneedling", "Chemical peel", "TCA CROSS",
        "Cortisone injection", "Filler", "Botox", "Extraction", "Cryotherapy", "Photodynamic therapy",
    ]

    /// Weeks after a procedure when Today asks for an "after" photo.
    public static let photoWeeks = [4, 12, 26]
    /// How long the "Day N after" card stays.
    public static let afterDays = 14
    /// How far ahead Today shows an upcoming procedure.
    public static let aheadDays = 7

    /// Laser, peels and needling: the sun note applies (docs/procedure-facts.md §2).
    public static func sunCare(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["laser", "peel", "needling", "tca", "resurfacing"].contains { n.contains($0) }
    }

    /// Scar treatments: the "works gradually" note applies (§3). Not vascular or pico laser.
    public static func scarTreatment(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["subcision", "needling", "co2", "erbium", "fractional", "resurfacing", "peel", "tca"].contains { n.contains($0) }
    }

    /// "4 weeks", "12 weeks", "6 months".
    public static func photoMark(_ weeks: Int) -> String {
        weeks >= 26 ? "\(weeks / 26 * 6) months" : "\(weeks) weeks"
    }

    /// Isotretinoin by its generic or common brand names.
    public static func takesIsotretinoin(_ s: AppState) -> Bool {
        let names = ["isotretinoin", "accutane", "roaccutane", "absorica", "claravis", "amnesteem", "zenatane", "myorisan", "isotrexin"]
        return s.products.contains { p in names.contains { p.name.lowercased().contains($0) } }
    }

    // MARK: Reading

    /// Today or later, soonest first.
    public static func upcoming(_ s: AppState, today: Day) -> [Procedure] {
        s.procedures.filter { $0.day >= today }.sorted { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
    }

    /// Before today, latest first.
    public static func past(_ s: AppState, today: Day) -> [Procedure] {
        s.procedures.filter { $0.day < today }.sorted { $0.day == $1.day ? $0.at > $1.at : $0.day > $1.day }
    }

    public static func on(_ s: AppState, _ day: Day) -> [Procedure] {
        s.procedures.filter { $0.day == day }
    }

    /// The next procedure on the same area after this one.
    /// Same-day procedures (subcision plus a laser) share one before and one after.
    static func next(after p: Procedure, in s: AppState) -> Procedure? {
        s.procedures.filter { $0.place == p.place && $0.day > p.day }
            .min { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
    }

    /// Earlier sessions of the same treatment on the same area, first one first.
    public static func series(_ p: Procedure, in s: AppState) -> [Procedure] {
        let key = p.name.trimmingCharacters(in: .whitespaces).lowercased()
        return s.procedures.filter { $0.place == p.place && $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key }
            .sorted { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
    }

    /// The "before": a photo from the day itself (the earliest that day, usually
    /// taken before the appointment), otherwise the latest one before it.
    public static func beforePhoto(_ p: Procedure, in s: AppState) -> PhotoMeta? {
        let latest: (PhotoMeta, PhotoMeta) -> Bool = { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
        let same = s.photos.filter { $0.place == p.place }
        // A procedure has no time, so a photo from the day itself could be from after the
        // appointment. The week before wins; the day itself only when there's nothing then.
        if let week = same.filter({ $0.day < p.day && $0.day.days(to: p.day) <= 7 }).max(by: latest) { return week }
        if let onDay = same.filter({ $0.day == p.day }).min(by: { $0.at < $1.at }) { return onDay }
        return same.filter { $0.day < p.day }.max(by: latest)
    }

    /// The "after": the latest photo since, up to the next session's "before".
    public static func afterPhoto(_ p: Procedure, in s: AppState) -> PhotoMeta? {
        let before = beforePhoto(p, in: s)
        if let n = next(after: p, in: s) {
            guard let b = beforePhoto(n, in: s), b.day > p.day, b.id != before?.id else { return nil }
            return b
        }
        return s.photos.filter { $0.place == p.place && $0.day > p.day }.max { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
    }

    /// A same-area photo from the week before (or the day of) the procedure.
    public static func recentBefore(_ p: Procedure, in s: AppState) -> PhotoMeta? {
        guard let b = beforePhoto(p, in: s), b.day.days(to: p.day) <= 7 else { return nil }
        return b
    }

    /// "Day of", "3 days after", "5 weeks after", "6 months after".
    public static func since(_ days: Int) -> String {
        switch days {
        case ..<1: return "Day of"
        case 1: return "1 day after"
        case 2..<14: return "\(days) days after"
        case 14..<120: return "\(days / 7) weeks after"
        default: return "\(days / 30) months after"
        }
    }

    /// How a photo relates to the procedures on the same area, for labels:
    /// "Before Subcision" or "5 weeks after Subcision".
    public static func context(_ photo: PhotoMeta, in s: AppState) -> String? {
        let same = s.procedures.filter { $0.place == photo.place }.sorted { $0.day < $1.day }
        if let soon = same.first(where: { $0.day >= photo.day && photo.day.days(to: $0.day) <= 7 && beforePhoto($0, in: s)?.id == photo.id }) {
            return "Before \(soon.name)"
        }
        // On the day itself: "Day of Subcision".
        if let last = same.last(where: { $0.day <= photo.day }) {
            return "\(since(last.day.days(to: photo.day))) \(last.name)"
        }
        return nil
    }

    /// The procedure whose actives break covers this routine on this day. A procedure's
    /// break wins over a travel pause on the same days.
    public static func breakFor(_ s: AppState, slot: Slot, on day: Day) -> Procedure? {
        for pause in s.pauses where pause.covers(day) && pause.applies(to: slot) {
            if let id = pause.procedureID, let p = s.procedures.first(where: { $0.id == id }) { return p }
        }
        return nil
    }

    /// The pause to show on Today: only one that touches a routine in use, and a
    /// procedure's break before any other.
    public static func bannerPause(_ s: AppState, today: Day) -> Pause? {
        let covering = s.pauses.filter { p in p.covers(today) && s.plan.activeSlots.contains { p.applies(to: $0) } }
        return covering.first { $0.procedureID != nil } ?? covering.first
    }

    // MARK: Today

    /// What Today should say about procedures, most pressing first.
    public static func moments(_ s: AppState, today: Day) -> [ProcedureMoment] {
        var soon: [ProcedureMoment] = []
        var later: [ProcedureMoment] = []
        for p in upcoming(s, today: today) {
            let n = today.days(to: p.day)
            guard n <= aheadDays else { break }
            if n <= 1 { soon.append(.upcoming(p, inDays: n)) } else { later.append(.upcoming(p, inDays: n)) }
        }
        var after: [ProcedureMoment] = []
        var photos: [ProcedureMoment] = []
        // Only the latest procedure per area: an older session's photo dates are moot.
        for area in Area.allCases {
            guard let p = past(s, today: today).first(where: { $0.place == area }) else { continue }
            let d = p.day.days(to: today)
            if d <= afterDays {
                let m = ProcedureMoment.after(p, day: d)
                if !s.dismissed.contains(m.dismissID!) { after.append(m) }
                continue
            }
            // Another session on this area within the week: its "before" covers it.
            if upcoming(s, today: today).contains(where: { $0.place == area && today.days(to: $0.day) <= aheadDays }) { continue }
            for w in photoWeeks.reversed() {
                let check = p.day.adding(w * 7)
                guard check <= today, check.days(to: today) < 14 else { continue }
                let m = ProcedureMoment.photo(p, weeks: w)
                let hasPhoto = s.photos.contains { $0.place == area && $0.day >= check }
                if !hasPhoto && !s.dismissed.contains(m.dismissID!) { photos.append(m) }
                break
            }
        }
        return soon + after + later + photos
    }
}

// MARK: - Changes

public extension AppState {
    /// Add or update a procedure, and move its actives break with it.
    mutating func saveProcedure(_ p: Procedure, today: Day) {
        var p = p
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = procedures.firstIndex(where: { $0.id == p.id }) { procedures[i] = p } else { procedures.append(p) }
        procedures.sort { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
        syncBreak(p.id, today: today)
    }

    /// Remove a procedure. A break that already happened stays in the history.
    mutating func removeProcedure(_ id: String, today: Day) {
        procedures.removeAll { $0.id == id }
        syncBreak(id, today: today)
        dismissed.removeAll { $0.hasPrefix("proc:\(id):") }
    }

    /// Rebuild a procedure's break. Days before today are history and keep
    /// what they were; today onward follows the procedure.
    internal mutating func syncBreak(_ id: String, today: Day) {
        let proc = procedures.first { $0.id == id }
        let existing = pauses.filter { $0.procedureID == id }
        pauses.removeAll { $0.procedureID == id }
        for e in existing where e.from < today {
            var past = e
            past.to = min(e.to, today.adding(-1))
            if proc == nil { past.procedureID = nil }
            pauses.append(past)
        }
        guard let p = proc, let w = p.breakDays else { return }
        let from = max(w.from, today)
        guard from <= w.to else { return }
        if let i = pauses.firstIndex(where: { $0.procedureID == id && $0.area == p.place && $0.to == from.adding(-1) }) {
            pauses[i].to = w.to
        } else {
            // Keep the id of the upcoming break this replaces, so an unchanged edit changes nothing.
            let reuse = existing.first { $0.from >= today }?.id ?? makeID()
            pauses.append(Pause(id: reuse, from: from, to: w.to, reason: .procedure, area: p.place, procedureID: id))
        }
    }
}
