import XCTest
@testable import BarrierCore

final class DayTests: XCTestCase {
    func testOrdinalRoundTripAndWeekday() {
        let d = Day(2026, 10, 5)
        XCTAssertEqual(Day(ordinal: d.ordinal), d)
        XCTAssertEqual(d.weekday, 1) // Monday
        XCTAssertEqual(Day(1970, 1, 1).weekday, 4) // Thursday
        XCTAssertEqual(Day(2024, 2, 28).adding(1), Day(2024, 2, 29))
        XCTAssertEqual(Day(2026, 12, 31).adding(1), Day(2027, 1, 1))
        XCTAssertEqual(Day(2026, 3, 1).days(to: Day(2026, 4, 1)), 31)
        XCTAssertEqual(Day(2026, 1, 31).addingMonths(1), Day(2026, 2, 28))
        XCTAssertEqual(Day(2026, 1, 15).addingMonths(-1), Day(2025, 12, 15))
        XCTAssertEqual(Day(iso: "2026-10-09"), Day(2026, 10, 9))
        XCTAssertNil(Day(iso: "nope"))
    }

    func testRoutineDayRollsOverAt4am() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        let lateNight = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 1, minute: 30))!
        XCTAssertEqual(Day.routineDay(lateNight, calendar: cal), Day(2026, 10, 9))
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 7))!
        XCTAssertEqual(Day.routineDay(morning, calendar: cal), Day(2026, 10, 10))
        // A 00:30 reminder on routine day Oct 9 fires on the calendar day Oct 10.
        XCTAssertEqual(DayTime(Day(2026, 10, 9), ClockTime(0, 30)).calendarDay, Day(2026, 10, 10))
    }
}

final class EngineTests: XCTestCase {
    let start = Day(2026, 10, 5) // a Monday

    func cycling() -> AppState {
        var s = Presets.apply(.cycling, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        return s
    }

    func done(_ d: Day, _ slot: Slot = .pm, recovery: Bool? = nil) -> Entry {
        Entry(day: d, slot: slot, status: .done, recovery: recovery)
    }

    func labels(_ s: AppState, _ from: Day, _ to: Day, today: Day) -> [String] {
        Engine.timeline(s, slot: .pm, from: from, to: to, today: today).map(\.label)
    }

    func testSkinCyclingProjects4Nights() {
        let s = cycling()
        XCTAssertEqual(labels(s, start, start.adding(5), today: start), [
            "Exfoliation night", "Retinoid night", "Recovery night", "Recovery night", "Exfoliation night", "Retinoid night",
        ])
        let hues = Engine.timeline(s, slot: .pm, from: start, to: start.adding(3), today: start).map(\.hue)
        XCTAssertEqual(hues, [.gold, .clay, .sage, .mist])
    }

    func testSkippedRetinoidNightRepeats() {
        var s = cycling()
        s.log = [done(start), Entry(day: start.adding(1), slot: .pm, status: .skipped)]
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: start.adding(2), today: start.adding(2)).label, "Retinoid night")
    }

    func testUnloggedActiveHoldsUnloggedRecoveryAdvances() {
        var s = cycling()
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: start.adding(1), today: start.adding(1)).label, "Exfoliation night")
        s.log = [done(start), done(start.adding(1))]
        XCTAssertEqual(labels(s, start.adding(2), start.adding(4), today: start.adding(4)), ["Recovery night", "Recovery night", "Exfoliation night"])
    }

    func testRecoveryNightDropsActivesAndHolds() {
        var s = cycling()
        s.log = [done(start), done(start.adding(1), recovery: true)]
        let tonight = Engine.instance(s, slot: .pm, on: start.adding(1), today: start.adding(1))
        XCTAssertEqual(tonight.label, "Recovery night")
        XCTAssertEqual(tonight.rest, .inserted)
        XCTAssertFalse(tonight.steps.contains(where: \.active))
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: start.adding(2), today: start.adding(2)).label, "Retinoid night")
    }

    func testPauseMakesSimpleNightsAndResumes() {
        var s = cycling()
        s.log = [done(start)]
        s.pauses = [Pause(from: start.adding(1), to: start.adding(3), reason: .travel)]
        let tl = Engine.timeline(s, slot: .pm, from: start.adding(1), to: start.adding(4), today: start.adding(1))
        XCTAssertEqual(tl.map(\.label), ["Simple night", "Simple night", "Simple night", "Retinoid night"])
        XCTAssertEqual(tl[0].steps.map(\.product.kind), [.cleanser, .moisturizer])
    }

    func testNextExfoliation() {
        let s = cycling()
        XCTAssertEqual(Engine.next(s, slot: .pm, today: start, where: { $0.product.kind == .exfoliant })?.day, start.adding(4))
    }

    func testRetinoidEaseIn() {
        var s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        s.log = (0..<34).map { done(start.adding($0)) }
        let tl = Engine.timeline(s, slot: .pm, from: start, to: start.adding(33), today: start.adding(40))
        let pattern = tl.map { $0.steps.contains { $0.product.kind == .retinoid } ? "R" : "." }.joined()
        XCTAssertEqual(pattern, "R..R..R..R..R.R.R.R.R.R.R.R.RRRRRR")
        XCTAssertTrue(tl[0].easing)
        XCTAssertFalse(tl[30].easing)
    }

    func testReconcileAsksAboutLastNightOnlyWhenActive() {
        var s = cycling()
        s.log = [done(start)]
        let r = Engine.needsReconcile(s, today: start.adding(2))
        XCTAssertEqual(r.map(\.day), [start.adding(1)])
        XCTAssertEqual(r.first?.label, "Retinoid night")
        s.log = [done(start), done(start.adding(1))]
        XCTAssertTrue(Engine.needsReconcile(s, today: start.adding(4)).isEmpty)
    }

    func testEveryOtherNightPlusAlternateTreatment() {
        var s = Presets.blankState(today: start)
        let clean = Product(name: "Cleanser", kind: .cleanser)
        let tret = Product(name: "Tretinoin 0.025%", kind: .retinoid)
        let aze = Product(name: "Azelaic acid 15%", kind: .treatment)
        s.products = [clean, tret, aze]
        let st = [Step(productId: clean.id), Step(productId: tret.id), Step(productId: aze.id)]
        s.plan.pm.steps = st
        let pm = Dictionary(uniqueKeysWithValues: s.products.map { ($0.id, $0) })
        var plan = Engine.setEvery(s.plan.pm, stepID: st[1].id, n: 2, products: pm)
        plan = Engine.setEvery(plan, stepID: st[2].id, n: 2, products: pm)
        s.plan.pm = plan
        s.onboarded = true
        XCTAssertEqual(plan.length, 2)
        XCTAssertEqual(labels(s, start, start.adding(3), today: start), ["Retinoid night", "Azelaic acid night", "Retinoid night", "Azelaic acid night"])
        XCTAssertEqual(Engine.describe(plan.steps[1], in: plan), "Every other night")
        XCTAssertEqual(Engine.every(of: plan.steps[2], length: plan.length), 2)
    }

    func testWeekdayStepsAndCourseWindows() {
        var s = Presets.blankState(today: start)
        let clean = Product(name: "Cleanser", kind: .cleanser)
        let ex = Product(name: "BHA", kind: .exfoliant)
        var pill = Product(name: "Doxycycline", kind: .oral)
        pill.until = start.adding(2)
        s.products = [clean, ex, pill]
        s.plan.pm.steps = [Step(productId: clean.id), Step(productId: ex.id, on: .weekdays([2, 6])), Step(productId: pill.id)]
        let tl = Engine.timeline(s, slot: .pm, from: start, to: start.adding(6), today: start)
        XCTAssertEqual(tl.map(\.label), ["Recovery night", "Exfoliation night", "Recovery night", "Recovery night", "Recovery night", "Exfoliation night", "Recovery night"])
        XCTAssertEqual(tl[2].lastDayOf.map(\.name), ["Doxycycline"])
        XCTAssertFalse(tl[3].steps.contains { $0.product.name == "Doxycycline" })
    }

    func testStatsAndRings() {
        var s = cycling()
        s.log = (0..<5).map { Entry(day: start.adding($0), slot: .pm, status: .done, label: "x") }
        XCTAssertEqual(Engine.stats(s, today: start.adding(4)).nightsDone, 5)
        let r = Engine.rings(s, today: start.adding(4))
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].segments.count, 4)
        XCTAssertTrue(r[0].segments.allSatisfy(\.done))
        XCTAssertNotNil(Milestones.reached(s, today: start.adding(4)).first { $0.id == "cycle-1" })
    }

    func testConflicts() {
        var s = Presets.blankState(today: start)
        let tret = Product(name: "Tretinoin 0.05%", kind: .retinoid)
        let bpo = Product(name: "Benzoyl peroxide 5%", kind: .treatment)
        let bha = Product(name: "BHA", kind: .exfoliant)
        s.products = [tret, bpo, bha]
        s.plan.pm.steps = [Step(productId: tret.id), Step(productId: bpo.id), Step(productId: bha.id)]
        let i = Engine.instance(s, slot: .pm, on: start, today: start)
        XCTAssertEqual(Set(i.conflicts), [.retinoidExfoliant, .bpoTretinoin])
    }

    func testRotationNodes() {
        let s = cycling()
        let nodes = Engine.rotationNodes(s, slot: .pm, on: start)
        XCTAssertEqual(nodes.map(\.hue), [.gold, .clay, .sage, .mist])
    }

    func testResizeKeepsPattern() {
        var sp = Presets.emptySlot(ClockTime(21, 0), today: start)
        sp.length = 2
        sp.steps = [Step(productId: "x", on: .nights([0]))]
        let r = Engine.resize(sp, to: 4)
        XCTAssertEqual(r.steps[0].on, .nights([0, 2]))
    }
}

final class MutationTests: XCTestCase {
    let start = Day(2026, 10, 5)

    func testInboxAppliesDoneFromNotification() {
        var s = Presets.apply(.cycling, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        s.apply([InboxItem(day: start, slot: .pm, action: .done)], today: start.adding(1))
        XCTAssertEqual(s.entry(start, .pm)?.status, .done)
        XCTAssertEqual(s.entry(start, .pm)?.label, "Exfoliation night")
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: start.adding(1), today: start.adding(1)).label, "Retinoid night")
    }

    func testRecoveryToggleAndClear() {
        var s = Presets.apply(.cycling, to: Presets.blankState(today: start), today: start)
        s.setRecovery(start, .pm, on: true)
        XCTAssertEqual(s.entry(start, .pm)?.status, .open)
        s.markDone(.pm, on: start, today: start)
        XCTAssertEqual(s.entry(start, .pm)?.recovery, true)
        s.clearEntry(start, .pm)
        XCTAssertEqual(s.entry(start, .pm)?.status, .open)
        s.setRecovery(start, .pm, on: false)
        XCTAssertNil(s.entry(start, .pm))
    }

    func testEndPause() {
        var s = Presets.blankState(today: start)
        s.addPause(from: start, to: start.adding(6), reason: .travel)
        s.endPause(s.pauses[0].id, today: start.adding(3))
        XCTAssertEqual(s.pauses[0].to, start.adding(2))
        s.addPause(from: start.adding(10), to: start.adding(12), reason: .travel)
        s.endPause(s.pauses[1].id, today: start.adding(3))
        XCTAssertEqual(s.pauses.count, 1)
    }

    func testStateRoundTripsAndToleratesMissingFields() throws {
        let s = Presets.demoState(today: start.adding(30))
        let data = try StateCoder.encode(s)
        let back = try StateCoder.decode(data)
        // Dates round to milliseconds, so compare the re-encoded bytes.
        XCTAssertEqual(try StateCoder.encode(back), data)
        XCTAssertEqual(back.plan, s.plan)
        XCTAssertEqual(back.log.count, s.log.count)
        // An old save with only the plan still loads.
        let planJSON = try StateCoder.encoder().encode(s.plan)
        let minimal = "{\"plan\":\(String(data: planJSON, encoding: .utf8)!)}"
        let old = try StateCoder.decode(Data(minimal.utf8))
        XCTAssertEqual(old.plan, s.plan)
        XCTAssertTrue(old.log.isEmpty)
        XCTAssertEqual(old.settings, Settings())
    }

    func testDemoStateLooksAlive() {
        let today = Day(2026, 11, 1)
        let s = Presets.demoState(today: today)
        let st = Engine.stats(s, today: today)
        XCTAssertGreaterThan(st.nightsDone, 15)
        XCTAssertFalse(Engine.rings(s, today: today).isEmpty)
    }
}

final class GuidanceTests: XCTestCase {
    func testTipsRotateAndFilter() {
        let t = Guidance.tip(for: [.cleanser], dayNumber: 3)
        XCTAssertTrue(["one", "photo"].contains(t.id))
        XCTAssertNotNil(Guidance.journey(kind: .retinoid, day: 10))
        XCTAssertEqual(Guidance.journey(kind: .retinoid, day: 10)?.title, "Week 2: settling in")
        XCTAssertNil(Guidance.journey(kind: .moisturizer, day: 10))
    }
}
