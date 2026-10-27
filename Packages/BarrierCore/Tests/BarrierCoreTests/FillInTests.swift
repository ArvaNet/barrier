import XCTest
@testable import BarrierCore

final class FillInTests: XCTestCase {
    /// Barrier set up on Oct 21; the routine was followed on paper since Oct 1.
    let setup = Day(2026, 10, 21)
    let paper = Day(2026, 10, 1)

    func base(_ template: Presets.Template = .retinoid) -> AppState {
        var s = Presets.apply(template, to: Presets.blankState(today: setup), today: setup)
        s.onboarded = true
        s.recordPlan(today: setup)
        return s
    }

    func entries(_ s: AppState, _ slot: Slot) -> [Entry] { s.log.filter { $0.slot == slot } }

    func testEveryDayBeforeTheStartCountsAsDone() {
        var s = base()
        s.fillIn(since: paper, missed: [:], today: setup)
        XCTAssertEqual(s.plan.createdAt, paper)
        XCTAssertEqual(entries(s, .pm).count, 20)
        XCTAssertEqual(entries(s, .am).count, 20)
        XCTAssertTrue(s.log.allSatisfy { $0.status == .done && $0.filledIn == true })
        XCTAssertEqual(s.log.map(\.day).min(), paper)
        XCTAssertEqual(s.log.map(\.day).max(), setup.adding(-1))
        XCTAssertEqual(s.filledInSpan?.from, paper)
        XCTAssertEqual(s.filledInSpan?.to, setup.adding(-1))
    }

    func testTheTreatmentAndTheEaseInStartedOnTheRealStart() {
        var s = base()
        s.fillIn(since: paper, missed: [:], today: setup)
        XCTAssertEqual(s.products.first { $0.kind == .retinoid }?.from, paper)
        XCTAssertEqual(s.plan.pm.steps.compactMap(\.buildUp).first?.start, paper)
        // So the filled-in weeks include tretinoin nights, not just the basics.
        XCTAssertTrue(entries(s, .pm).contains { $0.label?.lowercased().contains("retinoid") == true })
    }

    func testMissedDaysAreSkipped() {
        var s = base()
        let missed: Set<Day> = [Day(2026, 10, 5), Day(2026, 10, 6)]
        s.fillIn(since: paper, missed: [.pm: missed], today: setup)
        XCTAssertEqual(Set(entries(s, .pm).filter { $0.status == .skipped }.map(\.day)), missed)
        XCTAssertTrue(entries(s, .am).allSatisfy { $0.status == .done })
    }

    func testTonightStaysTonight() {
        var s = base(.cycling)
        let today = setup.adding(2)
        s.markDone(.pm, on: setup, today: today)
        let before = Engine.instance(s, slot: .pm, on: today, today: today)
        s.fillIn(since: paper, missed: [.pm: [Day(2026, 10, 9)]], today: today)
        let after = Engine.instance(s, slot: .pm, on: today, today: today)
        XCTAssertEqual(after.pos, before.pos)
        XCTAssertEqual(after.label, before.label)
    }

    func testTheChangeLogDoesNotCallItAChange() {
        var s = base()
        s.fillIn(since: paper, missed: [:], today: setup)
        s.recordPlan(today: setup.adding(1))
        XCTAssertEqual(s.history.first?.day, paper)
        XCTAssertTrue(PlanHistory.changes(s).isEmpty)
    }

    func testTheTimelineDrawsTheFilledInWeeks() {
        var s = base()
        s.fillIn(since: paper, missed: [:], today: setup)
        let t = TreatmentTimeline.build(s, today: setup)
        XCTAssertEqual(t.beforeDays, 0)
        let pm = t.rows.first { $0.slot == .pm }!
        XCTAssertTrue(pm.marks[t.index(paper)...].prefix(20).contains(.activeDone))
    }

    func testOnlyBeforeThePlanAndWithinTheWindow() {
        var s = base()
        let before = s
        s.fillIn(since: setup, missed: [:], today: setup)
        XCTAssertEqual(s, before)
        s.fillIn(since: setup.adding(-400), missed: [:], today: setup)
        XCTAssertEqual(s.plan.createdAt, AppState.fillInEarliest(today: setup))
        XCTAssertEqual(entries(s, .pm).count, 97)
    }

    func testABackRoutineAddedLaterIsLeftAlone() {
        var s = base()
        s.plan.body.enabled = true
        s.plan.body.anchor = Anchor(day: setup.adding(3), pos: 0)
        s.plan.body.steps = s.plan.am.steps
        XCTAssertFalse(s.fillInSlots().contains(.body))
        s.fillIn(since: paper, missed: [:], today: setup.adding(4))
        XCTAssertTrue(entries(s, .body).isEmpty)
    }

    func testDaysAlreadyLoggedAreKept() {
        var s = base()
        s.fillIn(since: Day(2026, 10, 10), missed: [:], today: setup)
        // A second, earlier fill-in adds the earlier days and keeps the rest.
        s.markSkipped(.pm, on: Day(2026, 10, 12), today: setup)
        s.fillIn(since: paper, missed: [:], today: setup)
        XCTAssertEqual(s.plan.createdAt, paper)
        XCTAssertEqual(s.entry(Day(2026, 10, 12), .pm)?.status, .skipped)
        XCTAssertEqual(entries(s, .pm).count, 20)
    }
}
