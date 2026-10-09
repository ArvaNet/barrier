import XCTest
@testable import BarrierCore

/// Regression tests for docs/review-1.md.
final class ReviewFixTests: XCTestCase {
    let start = Day(2026, 10, 5)

    /// #3: removing a step must not change what tonight is.
    func testRemovingAStepKeepsTonight() {
        var s = Presets.blankState(today: start)
        let clean = Product(name: "Cleanser", kind: .cleanser)
        let tret = Product(name: "Tretinoin", kind: .retinoid)
        let aze = Product(name: "Azelaic acid", kind: .treatment)
        s.products = [clean, tret, aze]
        let azeStep = Step(productId: aze.id, on: .nights([1]))
        s.plan.pm.length = 2
        s.plan.pm.steps = [Step(productId: clean.id), Step(productId: tret.id, on: .nights([0])), azeStep]
        s.onboarded = true
        s.log = [
            Entry(day: start, slot: .pm, status: .done),
            Entry(day: start.adding(1), slot: .pm, status: .skipped),
            Entry(day: start.adding(2), slot: .pm, status: .done),
        ]
        let today = start.adding(3)
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: today, today: today).label, "Retinoid night")
        s.editPlan(.pm, today: today) { st in
            st.plan.pm.steps.removeAll { $0.id == azeStep.id }
            st.pruneOrphanProducts()
        }
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: today, today: today).label, "Retinoid night")
    }

    /// #11: an unanswered "did it happen?" survives a plan edit.
    func testPendingQuestionSurvivesEdit() {
        var s = Presets.apply(.cycling, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        s.log = [Entry(day: start, slot: .pm, status: .done)]
        let today = start.adding(2)
        XCTAssertEqual(Engine.needsReconcile(s, today: today).map(\.day), [start.adding(1)])
        s.editPlan(.pm, today: today) { st in st.plan.pm.steps[0].amount = "A little" }
        XCTAssertEqual(Engine.needsReconcile(s, today: today).map(\.day), [start.adding(1)])
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: today, today: today).label, "Retinoid night")
    }

    /// #7: patterns that can't fit are refused instead of silently re-spaced.
    func testSetEveryRefusesWhatDoesNotFit() {
        var sp = Presets.emptySlot(ClockTime(21, 0), today: start)
        sp.length = 5
        let p = Product(name: "BHA", kind: .exfoliant)
        sp.steps = [Step(productId: p.id)]
        XCTAssertNil(Engine.setEvery(sp, stepID: sp.steps[0].id, n: 4, products: [p.id: p]))
        sp.length = 3
        XCTAssertEqual(Engine.setEvery(sp, stepID: sp.steps[0].id, n: 4, products: [p.id: p])?.length, 12)
    }

    /// #4: while tonight's active night is open, later reminders stay generic.
    func testRemindersAfterAnOpenActiveNightAreGeneric() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        var s = Presets.apply(.cycling, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        s.settings.photoDay = -1
        let noon = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        var r = Reminders.plan(s, now: noon, calendar: cal)
        XCTAssertEqual(r.first { $0.id == "\(start.iso):pm:main" }?.title, "Tonight: Exfoliation night")
        XCTAssertEqual(r.first { $0.id == "\(start.adding(1).iso):pm:main" }?.title, "Evening routine")
        s.log = [Entry(day: start, slot: .pm, status: .done)]
        r = Reminders.plan(s, now: noon, calendar: cal)
        XCTAssertEqual(r.first { $0.id == "\(start.adding(1).iso):pm:main" }?.title, "Tonight: Retinoid night")
    }

    /// #2: one unreadable entry doesn't wipe the log.
    func testOneBadEntryDoesNotWipeTheLog() throws {
        var s = Presets.blankState(today: start)
        s.log = [Entry(day: start.adding(20), slot: .pm, status: .done), Entry(day: start.adding(21), slot: .pm, status: .done)]
        var json = String(data: try StateCoder.encode(s), encoding: .utf8)!
        json = json.replacingOccurrences(of: "2026-10-25", with: "garbage")
        let back = try StateCoder.decode(Data(json.utf8))
        XCTAssertEqual(back.log.count, 1)
        XCTAssertEqual(back.log.first?.day, start.adding(21))
    }

    /// #5: day math is Gregorian whatever the phone's calendar.
    func testDayMathIgnoresDisplayCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let date = buddhist.date(from: DateComponents(year: 2569, month: 10, day: 9, hour: 21))!
        var greg = Calendar.barrier
        greg.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        XCTAssertEqual(Day.of(date, calendar: greg), Day(2026, 10, 9))
        XCTAssertEqual(Day(2026, 10, 9).weekday, 5) // Friday
    }
}
