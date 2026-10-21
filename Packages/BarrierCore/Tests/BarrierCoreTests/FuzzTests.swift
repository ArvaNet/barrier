import XCTest
@testable import BarrierCore

/// Simulated users, day by day: logging, skipping, recovery nights, pauses, procedures,
/// plan edits and fill-ins. Then every calculation the screens use runs, and the rules
/// that must never break are checked. Seeded, so a failure always reproduces.
final class FuzzTests: XCTestCase {
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        return c
    }()

    /// One simulated user. Returns the state and the day it ends on.
    func simulate(seed: UInt64) -> (AppState, Day) {
        var rng = SeededRNG(state: seed)
        func roll(_ n: Int) -> Int { Int.random(in: 0..<n, using: &rng) }
        func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

        let start = Day(2026, 1, 1).adding(roll(330))
        let template: Presets.Template = [.retinoid, .cycling, .simple][roll(3)]
        var s = Presets.apply(template, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        s.settings.photoDay = -1
        if chance(0.4) { s.plan.pm.easeIn = nil }
        if chance(0.2) { s.plan.am.enabled = false }
        if chance(0.5) {
            let lotion = Product(name: "Clindamycin lotion", kind: .treatment)
            s.products.append(lotion)
            var step = Step(productId: lotion.id)
            if chance(0.3) { step.on = .weekdays([1, 3, 5]) }
            s.plan.body = SlotPlan(enabled: true, time: ClockTime(20, 30), steps: [step],
                                   anchor: Anchor(day: start.adding(roll(20)), pos: 0), name: "Back", cue: "After shower")
        }
        s.recordPlan(today: start)

        let length = 40 + roll(100)
        var edits = 0
        for n in 0..<length {
            let d = start.adding(n)
            let at = Date(timeIntervalSince1970: TimeInterval(d.ordinal) * 86_400)
            if chance(0.02) {
                let a = d.adding(roll(10))
                s.addPause(from: a, to: a.adding(roll(7)), reason: PauseReason.allCases[roll(PauseReason.allCases.count)])
            }
            if chance(0.015) {
                let p = Procedure(name: ["Subcision", "Chemical peel", "Microneedling"][roll(3)], day: d.adding(roll(25) - 5),
                                  area: chance(0.7) ? .face : .body, breakBefore: roll(6), breakAfter: roll(11))
                s.saveProcedure(p, today: d)
            }
            if edits < 2 && chance(0.02) {
                edits += 1
                let newLength = 1 + roll(4)
                s.editPlan(.pm, today: d) { $0.plan.pm.length = newLength }
                s.recordPlan(today: d)
            }
            for slot in [Slot.pm, .am, .body] where s.plan[slot].enabled {
                switch roll(20) {
                case 0..<13: s.markDone(slot, on: d, today: d, at: at)
                case 13..<15: s.markSkipped(slot, on: d, today: d)
                case 15: s.setRecovery(d, slot, on: true); s.markDone(slot, on: d, today: d, at: at)
                default: break // not logged
                }
            }
            if chance(0.15) { s.checkIn(d, feel: [Feeling.allCases[roll(Feeling.allCases.count)]], area: chance(0.8) ? .face : .body) }
            if chance(0.1) { s.setScore(1 + roll(5), day: d, area: .face, at: at) }
        }
        return (s, start.adding(length))
    }

    /// Everything the screens compute, plus the rules that must hold. Returns problems found.
    func problems(_ s: AppState, today: Day, tag: String) -> [String] {
        var out: [String] = []
        func fail(_ m: String) { out.append("\(tag): \(m)") }

        for slot in [Slot.pm, .am, .body] {
            let sp = s.plan[slot]
            let from = s.plan.createdAt
            let tl = Engine.timeline(s, slot: slot, from: from, to: today.adding(21), today: today)
            if tl.count != from.days(to: today.adding(21)) + 1 { fail("\(slot) timeline has \(tl.count) days") }

            // A rest of any kind (rotation rest, recovery night, pause or a procedure's break)
            // never puts a treatment on the skin.
            for i in tl where i.rest != nil && i.steps.contains(where: { $0.product.kind.isActive }) {
                fail("\(slot) \(i.day): active step on a rest night (\(String(describing: i.rest)))")
            }
            // The rotation never skips ahead: from one night to the next it stays or moves one.
            if sp.enabled {
                for (a, b) in zip(tl, tl.dropFirst()) where a.day >= sp.anchor.day && a.cycleLen == b.cycleLen && a.cycleLen > 0 {
                    if b.pos != a.pos && b.pos != (a.pos + 1) % a.cycleLen {
                        fail("\(slot) \(a.day)->\(b.day): position \(a.pos)->\(b.pos) of \(a.cycleLen)")
                    }
                }
            }
            // One day asked on its own agrees with the same day in the range.
            for i in stride(from: 0, to: tl.count, by: 9) {
                let one = Engine.instance(s, slot: slot, on: tl[i].day, today: today)
                if one.pos != tl[i].pos || one.label != tl[i].label || one.status != tl[i].status
                    || one.steps.map(\.step.id) != tl[i].steps.map(\.step.id) {
                    fail("\(slot) \(tl[i].day): single day differs from the range")
                }
            }
            // Every night up to today that has steps is either logged or open, never "future".
            for i in tl where i.day < today && i.status == .future { fail("\(slot) \(i.day): past day marked future") }
        }

        let st = Engine.stats(s, today: today)
        if st.last28Done > st.last28Due { fail("stats: \(st.last28Done) done of \(st.last28Due) due") }
        _ = Engine.rings(s, today: today)
        _ = Engine.needsReconcile(s, today: today)
        _ = Milestones.reached(s, today: today)
        _ = Milestones.unseen(s, today: today)
        _ = Recaps.lastWeek(s, today: today)
        _ = Procedures.moments(s, today: today)
        _ = PlanHistory.changes(s)

        for days in [98, 56] {
            let t = TreatmentTimeline.build(s, today: today, maxDays: days)
            for row in t.rows {
                if row.marks.count != t.days { fail("timeline \(days): \(row.slot) has \(row.marks.count) marks for \(t.days) days") }
                let c = t.counts(row.slot)
                if c.done > c.due { fail("timeline \(days): \(row.slot) \(c.done) done of \(c.due)") }
            }
            if t.days > days { fail("timeline \(days): \(t.days) days") }
        }

        let now = DayTime(today, ClockTime(12, 0)).date(calendar: cal)
        let reminders = Reminders.plan(s, now: now, calendar: cal)
        if Set(reminders.map(\.id)).count != reminders.count { fail("reminders: duplicate ids") }
        if reminders.count > 64 { fail("reminders: \(reminders.count) planned, iOS keeps 64") }
        for r in reminders where r.fire.date(calendar: cal).addingTimeInterval(TimeInterval(r.offsetMin * 60)) < now.addingTimeInterval(-60) {
            fail("reminders: \(r.id) fires in the past")
        }

        do {
            let a = try StateCoder.encode(s)
            let b = try StateCoder.encode(try StateCoder.decode(a))
            if a != b { fail("save file changes after a round trip") }
        } catch {
            fail("save file: \(error)")
        }
        return out
    }

    func testSimulatedUsersNeverBreakTheRules() {
        var all: [String] = []
        // Proof the simulation reaches the tricky cases, so passing means something.
        var seen = (pauses: 0, procedureBreaks: 0, recoveries: 0, edits: 0, restNights: 0, filled: 0, bodyUsers: 0)
        for seed in UInt64(1)...150 {
            let (s, today) = simulate(seed: seed)
            all += problems(s, today: today, tag: "seed \(seed)")
            seen.pauses += s.pauses.filter { $0.procedureID == nil }.count
            seen.procedureBreaks += s.pauses.filter { $0.procedureID != nil }.count
            seen.recoveries += s.log.filter { $0.recovery == true }.count
            seen.edits += max(0, s.history.count - 1)
            seen.restNights += Engine.timeline(s, slot: .pm, from: s.plan.createdAt, to: today, today: today).filter { $0.rest != nil }.count
            if s.plan.body.enabled { seen.bodyUsers += 1 }

            // The same user fills in the weeks before Barrier: still sound, tonight unchanged.
            var rng = SeededRNG(state: seed &* 7919)
            var f = s
            let back = 1 + Int.random(in: 0..<40, using: &rng)
            let since = f.plan.createdAt.adding(-back)
            let missedDays = Set((0..<back).filter { _ in Int.random(in: 0..<6, using: &rng) == 0 }.map { since.adding($0) })
            let tonightBefore = Engine.instance(f, slot: .pm, on: today, today: today)
            f.fillIn(since: since, missed: [.pm: missedDays, .am: missedDays], today: today)
            if f.filledInSpan != nil { seen.filled += 1 }
            all += problems(f, today: today, tag: "seed \(seed) filled in")
            let tonightAfter = Engine.instance(f, slot: .pm, on: today, today: today)
            if f.plan.pm.easeIn == nil && tonightAfter.label != tonightBefore.label {
                all.append("seed \(seed) filled in: tonight changed from \(tonightBefore.label) to \(tonightAfter.label)")
            }
        }
        XCTAssertTrue(all.isEmpty, "\(all.count) problems, first ones:\n" + all.prefix(15).joined(separator: "\n"))
        print("Fuzz coverage: \(seen)")
        XCTAssertGreaterThan(seen.pauses, 20)
        XCTAssertGreaterThan(seen.procedureBreaks, 10)
        XCTAssertGreaterThan(seen.recoveries, 100)
        XCTAssertGreaterThan(seen.edits, 30)
        XCTAssertGreaterThan(seen.restNights, 1000)
        // Users with more than 14 weeks in the app have no room to fill in: that's by design.
        XCTAssertGreaterThan(seen.filled, 60)
        XCTAssertGreaterThan(seen.bodyUsers, 40)
    }
}
