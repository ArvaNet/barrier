import XCTest
@testable import BarrierCore

final class HistoryTests: XCTestCase {
    let start = Day(2026, 10, 5)

    func base() -> AppState {
        var s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        s.plan.pm.easeIn = nil
        s.onboarded = true
        s.recordPlan(today: start)
        return s
    }

    func tret(_ s: AppState) -> Product { s.products.first { $0.kind == .retinoid }! }

    // MARK: Change log

    func testTheStartingRoutineIsNotAChange() {
        let s = base()
        XCTAssertEqual(s.history.count, 1)
        XCTAssertTrue(PlanHistory.changes(s).isEmpty)
    }

    func testEditsOnOneDayAreOneChange() {
        var s = base()
        let day = start.adding(3)
        let t = tret(s)
        let i = s.plan.pm.steps.firstIndex { $0.productId == t.id }!
        s.plan.pm.steps[i].amount = "Pea"
        s.recordPlan(today: day)
        s.plan.pm.steps[i].amount = "Pea-sized"
        s.recordPlan(today: day)
        let changes = PlanHistory.changes(s)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].day, day)
        XCTAssertEqual(changes[0].lines, ["\(t.name): Pea-size for the whole face → Pea-sized"])
    }

    func testADayThatUndidItselfLeavesNoTrace() {
        var s = base()
        let day = start.adding(3)
        let before = s.plan.pm.steps
        s.plan.pm.steps.removeLast()
        s.recordPlan(today: day)
        s.plan.pm.steps = before
        s.recordPlan(today: day)
        XCTAssertEqual(s.history.count, 1)
        XCTAssertTrue(PlanHistory.changes(s).isEmpty)
    }

    func testARenameIsNotAChange() {
        var s = base()
        let t = tret(s)
        s.products[s.products.firstIndex { $0.id == t.id }!].name = "Tretinoin cream"
        s.recordPlan(today: start.adding(2))
        XCTAssertEqual(s.history.count, 1)
    }

    func testScheduleAddStopAndMoveRead() {
        var s = base()
        let t = tret(s)
        // Every night instead of a rotation.
        s.plan.pm.length = 2
        let i = s.plan.pm.steps.firstIndex { $0.productId == t.id }!
        s.plan.pm.steps[i].on = .nights([0])
        s.recordPlan(today: start.adding(1))
        s.plan.pm.steps[i].on = .all
        s.recordPlan(today: start.adding(5))
        // An azelaic acid added to mornings, then the moisturizer stopped at night.
        let aze = Product(name: "Azelaic acid 15%", kind: .treatment)
        s.products.append(aze)
        s.plan.am.enabled = true
        s.plan.am.steps.append(Step(productId: aze.id))
        s.recordPlan(today: start.adding(8))
        // Tretinoin moves to the morning (unusual, but the log should say "moved").
        let step = s.plan.pm.steps.remove(at: i)
        s.plan.am.steps.append(step)
        s.recordPlan(today: start.adding(10))

        let lines = PlanHistory.changes(s).map(\.lines)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], ["\(t.name): every night → every other night"])
        XCTAssertEqual(lines[1],["\(t.name): every other night → every night"])
        XCTAssertEqual(lines[2], ["Azelaic acid 15%: added to morning, every morning"])
        XCTAssertEqual(lines[3], ["\(t.name): moved from evening to morning, every morning"])
    }

    func testABodyRoutineStartingIsOneLine() {
        var s = base()
        let lotion = Product(name: "Clindamycin lotion", kind: .treatment)
        s.products.append(lotion)
        s.plan.body = SlotPlan(enabled: true, time: ClockTime(20, 30), steps: [Step(productId: lotion.id)], anchor: Anchor(day: start, pos: 0), name: "Back")
        s.recordPlan(today: start.adding(4))
        XCTAssertEqual(PlanHistory.changes(s).first?.lines, ["Back routine started: Clindamycin lotion"])
        s.plan.body.enabled = false
        s.recordPlan(today: start.adding(9))
        XCTAssertEqual(PlanHistory.changes(s).last?.lines, ["Back routine stopped"])
    }

    func testCourseEndAndEaseIn() {
        var s = base()
        let t = tret(s)
        s.products[s.products.firstIndex { $0.id == t.id }!].until = Day(2026, 12, 1)
        s.plan.pm.easeIn = EaseIn(start: start.adding(2), phases: Presets.easeInPhases)
        s.recordPlan(today: start.adding(2))
        let lines = PlanHistory.changes(s).first?.lines ?? []
        XCTAssertTrue(lines.contains("\(t.name): course until Dec 1"))
        XCTAssertTrue(lines.contains("Evening: easing in"))
    }

    func testOldSavesWithoutHistoryOrScoresLoad() throws {
        var s = base()
        s.setScore(4, day: start, area: .face)
        var obj = try JSONSerialization.jsonObject(with: try StateCoder.encode(s)) as! [String: Any]
        obj.removeValue(forKey: "history")
        obj.removeValue(forKey: "scores")
        let back = try StateCoder.decode(try JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(back.history.isEmpty)
        XCTAssertTrue(back.scores.isEmpty)
        // And round-trips with them.
        let again = try StateCoder.decode(try StateCoder.encode(s))
        XCTAssertEqual(again.history, s.history)
        XCTAssertEqual(again.scores.map(\.value), s.scores.map(\.value))
        XCTAssertEqual(again.scores.map(\.day), s.scores.map(\.day))
    }

    // MARK: Scores

    func testScoresAreWeeklyAndOnePerDay() {
        var s = base()
        XCTAssertTrue(Scores.isDue(s, area: .face, today: start), "the first one right away")
        s.setScore(2, day: start, area: .face)
        s.setScore(3, day: start, area: .face)
        XCTAssertEqual(s.scores.map(\.value), [3], "a second tap the same day replaces the first")
        XCTAssertFalse(Scores.isDue(s, area: .face, today: start.adding(6)))
        XCTAssertTrue(Scores.isDue(s, area: .face, today: start.adding(7)))
        XCTAssertTrue(Scores.isDue(s, area: .body, today: start))
        s.setScore(nil, day: start, area: .face)
        XCTAssertTrue(s.scores.isEmpty)
        XCTAssertEqual(Scores.label(1), "Rough")
        XCTAssertEqual(Scores.label(5), "Great")
        XCTAssertEqual(SkinScore(day: start, value: 9).value, 5)
    }

    // MARK: Timeline

    func testTimelineMarksWhatHappened() {
        var s = base()
        s.plan.pm.length = 2
        let t = tret(s)
        let i = s.plan.pm.steps.firstIndex { $0.productId == t.id }!
        s.plan.pm.steps[i].on = .nights([0])
        let today = start.adding(4)
        // Day 0 done (retinoid), day 1 done (rest), day 2 skipped (retinoid), day 3 nothing logged.
        s.markDone(.pm, on: start, today: today)
        s.markDone(.pm, on: start.adding(1), today: today)
        s.markSkipped(.pm, on: start.adding(2), today: today)
        s.checkIn(start.adding(1), feel: [.dry])
        s.checkIn(start.adding(2), feel: [.red])
        s.setScore(3, day: start, area: .face)
        s.photos.append(PhotoMeta(day: start.adding(1)))
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(3), breakBefore: 0, breakAfter: 0), today: start)
        let tl = TreatmentTimeline.build(s, today: today)
        XCTAssertEqual(tl.from, start)
        XCTAssertEqual(tl.days, 5)
        let pm = tl.rows.first { $0.slot == .pm }!
        XCTAssertEqual(pm.marks[0], .activeDone)
        XCTAssertEqual(pm.marks[1], .basicsDone)
        XCTAssertEqual(pm.marks[2], .activeMissed)
        XCTAssertEqual(pm.marks[3], .basicsMissed, "the peel's break day: basics only, not logged")
        XCTAssertEqual(pm.marks[4], .pending)
        XCTAssertEqual(tl.counts(.pm).done, 2)
        XCTAssertEqual(tl.counts(.pm).due, 4)
        XCTAssertEqual(tl.skin[1], .symptoms)
        XCTAssertEqual(tl.skin[2], .irritated)
        XCTAssertEqual(tl.scores.map(\.value), [3])
        XCTAssertEqual(tl.photos, [1])
        XCTAssertEqual(tl.procedures.map(\.name), ["Chemical peel"])
        XCTAssertEqual(tl.breaks, [TreatmentTimeline.Band(from: 3, to: 3, label: "Actives break")])
    }

    func testTimelineIsCappedAndStartsWithTheFirstThingWorthShowing() {
        var s = base()
        let today = start.adding(200)
        let tl = TreatmentTimeline.build(s, today: today)
        XCTAssertEqual(tl.days, 98)
        XCTAssertEqual(tl.to, today)
        // A peel before the plan started pulls the start back.
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(-10)), today: start)
        XCTAssertEqual(TreatmentTimeline.build(s, today: start.adding(5)).from, start.adding(-10))
    }

    func testDemoHasAStory() {
        let today = Day(2026, 10, 21)
        let s = Presets.demoState(today: today)
        let changes = PlanHistory.changes(s)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].lines, ["Back routine started: Clindamycin lotion"])
        XCTAssertEqual(changes[1].lines, ["Azelaic acid 15%: added to morning, every morning"])
        XCTAssertTrue(Scores.isDue(s, area: .face, today: today))
        XCTAssertTrue(Scores.isDue(s, area: .body, today: today))
        let tl = TreatmentTimeline.build(s, today: today)
        XCTAssertEqual(tl.from, today.adding(-23 - 31), "starts at the photo before the peel")
        XCTAssertEqual(tl.changes.map(\.number), [1, 2])
        XCTAssertEqual(tl.procedures.count, 2)
        XCTAssertFalse(tl.breaks.isEmpty)
    }
}
