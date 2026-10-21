import XCTest
@testable import BarrierCore

final class HistoryTests: XCTestCase {
    let start = Day(2026, 10, 5)

    /// Tretinoin every night, no ease-in, the starting routine noted on day 0.
    func base() -> AppState {
        var s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        s.plan.pm.easeIn = nil
        s.onboarded = true
        s.recordPlan(today: start)
        return s
    }

    func tret(_ s: AppState) -> Product { s.products.first { $0.kind == .retinoid }! }
    func tretStep(_ s: AppState) -> Int { s.plan.pm.steps.firstIndex { $0.productId == tret(s).id }! }

    // MARK: Change log

    func testTheStartingRoutineIsNotAChange() {
        let s = base()
        XCTAssertEqual(s.history.count, 1)
        XCTAssertTrue(PlanHistory.changes(s).isEmpty)
    }

    func testEditsOnOneDayAreOneChange() {
        var s = base()
        let day = start.adding(3)
        let i = tretStep(s)
        s.plan.pm.steps[i].amount = "Pea"
        s.recordPlan(today: day)
        s.plan.pm.steps[i].amount = "Pea-sized"
        s.recordPlan(today: day)
        let changes = PlanHistory.changes(s)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].day, day)
        XCTAssertEqual(changes[0].number, 1)
        XCTAssertEqual(changes[0].lines, ["Tretinoin: amount pea-size for the whole face → pea-sized"])
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
        XCTAssertTrue(PlanHistory.changes(s).isEmpty)
    }

    func testAStrengthChangeIsAChangeAndOldLinesKeepTheirName() {
        var s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        s.plan.pm.easeIn = nil
        s.onboarded = true
        let t = tret(s)
        s.products[s.products.firstIndex { $0.id == t.id }!].name = "Tretinoin 0.025% cream"
        s.recordPlan(today: start)
        s.plan.pm.steps[tretStep(s)].amount = "Pea-size"
        s.recordPlan(today: start.adding(2))
        s.products[s.products.firstIndex { $0.id == t.id }!].name = "Tretinoin 0.05% cream"
        s.recordPlan(today: start.adding(9))
        let lines = PlanHistory.changes(s).map(\.lines)
        XCTAssertEqual(lines, [
            ["Tretinoin 0.025% cream: amount pea-size for the whole face → pea-size"],
            ["Tretinoin: 0.025% → 0.05%"],
        ])
    }

    func testScheduleAddStopAndMoveRead() {
        var s = base()
        let i = tretStep(s)
        s.plan.pm.length = 2
        s.plan.pm.steps[i].on = .nights([0])
        s.recordPlan(today: start.adding(1))
        s.plan.pm.steps[i].on = .all
        s.recordPlan(today: start.adding(5))
        let aze = Product(name: "Azelaic acid 15%", kind: .treatment)
        s.products.append(aze)
        s.plan.am.steps.append(Step(productId: aze.id))
        s.recordPlan(today: start.adding(8))
        var weekdays = Step(productId: Product(name: "Exfoliant", kind: .exfoliant).id, on: .weekdays([1, 3, 5]))
        let ex = Product(id: weekdays.productId, name: "Glycolic toner", kind: .exfoliant)
        s.products.append(ex)
        weekdays.productId = ex.id
        s.plan.am.steps.append(weekdays)
        s.recordPlan(today: start.adding(9))
        let step = s.plan.pm.steps.remove(at: i)
        s.plan.am.steps.append(step)
        s.recordPlan(today: start.adding(10))

        let lines = PlanHistory.changes(s).map(\.lines)
        XCTAssertEqual(lines, [
            ["Tretinoin: every night → every other night"],
            ["Tretinoin: every other night → every night"],
            ["Azelaic acid 15%: started, every morning"],
            ["Glycolic toner: started in the morning, Mon, Wed, Fri"],
            ["Tretinoin: moved from evening to morning, every morning"],
        ])
    }

    func testRemovedAndAddedAgainIsNotTwoLines() {
        var s = base()
        let old = tret(s)
        let i = tretStep(s)
        let amount = s.plan.pm.steps[i].amount
        s.products.removeAll { $0.id == old.id }
        s.plan.pm.steps.remove(at: i)
        let again = Product(name: "Tretinoin", kind: .retinoid)
        s.products.append(again)
        s.plan.pm.steps.insert(Step(productId: again.id, amount: amount), at: i)
        s.recordPlan(today: start.adding(3))
        XCTAssertTrue(PlanHistory.changes(s).isEmpty, "\(PlanHistory.changes(s).map(\.lines))")
    }

    func testStartingOverSaysWhatReallyChanged() {
        var s = base()
        s = Presets.apply(.simple, to: s, today: start.adding(4))
        s.recordPlan(today: start.adding(4))
        let lines = PlanHistory.changes(s).first?.lines ?? []
        XCTAssertEqual(lines.first, "Tretinoin: stopped (evening)", "\(lines)")
        XCTAssertFalse(lines.contains { $0.contains("started") }, "\(lines)")
    }

    func testABodyRoutineStartingIsOneLine() {
        var s = base()
        let lotion = Product(name: "Clindamycin lotion", kind: .treatment)
        s.products.append(lotion)
        s.plan.body = SlotPlan(enabled: true, time: ClockTime(20, 30), steps: [Step(productId: lotion.id)], anchor: Anchor(day: start, pos: 0), name: "KP arms")
        s.recordPlan(today: start.adding(4))
        XCTAssertEqual(PlanHistory.changes(s).first?.lines, ["KP arms routine started: Clindamycin lotion, every day"])
        s.plan.body.enabled = false
        s.recordPlan(today: start.adding(9))
        XCTAssertEqual(PlanHistory.changes(s).last?.lines, ["KP arms routine stopped"])
    }

    func testCourseEndEaseInAndAFutureStart() {
        var s = base()
        let t = tret(s)
        s.products[s.products.firstIndex { $0.id == t.id }!].until = Day(2026, 12, 1)
        s.plan.pm.easeIn = EaseIn(start: start.adding(2), phases: Presets.easeInPhases)
        s.recordPlan(today: start.adding(2))
        let lines = PlanHistory.changes(s).first?.lines ?? []
        XCTAssertTrue(lines.contains("Tretinoin: course until Dec 1"), "\(lines)")
        XCTAssertTrue(lines.contains("Evening: easing in, full routine from Nov 4"), "\(lines)")

        let aze = Product(name: "Azelaic acid", kind: .treatment, from: start.adding(20))
        s.products.append(aze)
        s.plan.am.steps.append(Step(productId: aze.id))
        s.recordPlan(today: start.adding(3))
        XCTAssertEqual(PlanHistory.changes(s).last?.lines, ["Azelaic acid: started, every morning, from Oct 25"])
        s.products[s.products.firstIndex { $0.id == aze.id }!].from = start.adding(25)
        s.recordPlan(today: start.adding(4))
        XCTAssertEqual(PlanHistory.changes(s).last?.lines, ["Azelaic acid: start moved to Oct 30"])
    }

    func testAClockSetAheadDoesNotFreezeTheLog() {
        var s = base()
        s.plan.pm.steps[tretStep(s)].amount = "Pea"
        s.recordPlan(today: start.adding(365))
        // The clock is right again.
        s.plan.pm.steps[tretStep(s)].amount = "Two peas"
        s.recordPlan(today: start.adding(2))
        XCTAssertEqual(s.history.last?.day, start.adding(2))
        s.plan.pm.steps[tretStep(s)].on = .nights([0])
        s.plan.pm.length = 2
        s.recordPlan(today: start.adding(3))
        XCTAssertEqual(PlanHistory.changes(s).map(\.day), [start.adding(2), start.adding(3)])
    }

    func testAnOlderSaveCountsItsFirstDaysEdits() {
        var s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        let day = start.adding(30)
        s.recordPlan(today: day, start: true)
        s.plan.pm.steps[tretStep(s)].amount = "Pea"
        s.recordPlan(today: day)
        XCTAssertEqual(PlanHistory.changes(s).count, 1)
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
        let again = try StateCoder.decode(try StateCoder.encode(s))
        XCTAssertEqual(again.history.map(\.items), s.history.map(\.items))
        XCTAssertEqual(again.history.first?.plan, s.history.first?.plan)
        XCTAssertEqual(again.scores.map(\.value), s.scores.map(\.value))
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
        s.plan.pm.steps[tretStep(s)].on = .nights([0])
        s.recordPlan(today: start)
        let today = start.adding(4)
        s.markDone(.pm, on: start, today: today)
        s.markDone(.pm, on: start.adding(1), today: today)
        s.markSkipped(.pm, on: start.adding(2), today: today)
        s.checkIn(start.adding(1), feel: [.dry])
        s.checkIn(start.adding(2), feel: [.red])
        s.checkIn(start.adding(2), feel: [.red], area: .body)
        s.setScore(3, day: start, area: .face)
        s.photos.append(PhotoMeta(day: start.adding(1)))
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(3), session: 1, sessions: 2, breakBefore: 0, breakAfter: 0), today: start)
        let tl = TreatmentTimeline.build(s, today: today)
        XCTAssertEqual(tl.days, 14, "at least two weeks, so a new routine isn't giant blocks")
        XCTAssertEqual(tl.beforeDays, 9)
        func at(_ d: Int) -> TreatmentTimeline.Mark { tl.rows.first { $0.slot == .pm }!.marks[tl.index(start.adding(d))] }
        XCTAssertEqual(at(0), .activeDone)
        XCTAssertEqual(at(1), .basicsDone)
        XCTAssertEqual(at(2), .activeMissed)
        XCTAssertEqual(at(3), .basicsMissed, "the peel's break day: basics only, not logged")
        XCTAssertEqual(at(4), .pending)
        XCTAssertEqual(tl.counts(.pm).done, 2)
        XCTAssertEqual(tl.counts(.pm).due, 4)
        XCTAssertEqual(tl.skin[tl.index(start.adding(1))], .symptoms)
        XCTAssertEqual(tl.skin[tl.index(start.adding(2))], .irritated)
        XCTAssertEqual(tl.bodySkin[tl.index(start.adding(2))], .irritated, "back check-ins get their own row")
        XCTAssertEqual(tl.scores.map(\.value), [3])
        XCTAssertEqual(tl.photos, [tl.index(start.adding(1))])
        XCTAssertEqual(tl.procedures.map(\.name), ["Chemical peel 1/2"])
        XCTAssertEqual(tl.breaks, [TreatmentTimeline.Band(from: tl.index(start.adding(3)), to: tl.index(start.adding(3)), label: "Actives break", area: .face)])
    }

    func testAnEditKeepsTheDaysBeforeIt() {
        var s = base()
        let day6 = start.adding(6)
        s.markDone(.pm, on: start, today: day6)
        s.markDone(.pm, on: start.adding(1), today: day6)
        s.markSkipped(.pm, on: start.adding(2), today: day6)
        s.markDone(.pm, on: start.adding(4), today: day6)
        s.markDone(.pm, on: start.adding(5), today: day6)
        // A note fix in the step editor moves the routine's anchor to today.
        let i = tretStep(s)
        s.editPlan(.pm, today: day6) { $0.plan.pm.steps[i].how = "On dry skin" }
        s.recordPlan(today: day6)
        XCTAssertEqual(s.plan.pm.anchor.day, day6)
        let tl = TreatmentTimeline.build(s, today: day6)
        let pm = tl.rows.first { $0.slot == .pm }!
        let marks = (0..<6).map { pm.marks[tl.index(start.adding($0))] }
        XCTAssertEqual(marks, [.activeDone, .activeDone, .activeMissed, .activeMissed, .activeDone, .activeDone])
        XCTAssertEqual(tl.counts(.pm).done, 4)
        XCTAssertEqual(tl.counts(.pm).due, 6)
    }

    func testARoutineTurnedOffAndOnAgain() {
        var s = base()
        let lotion = Product(name: "Clindamycin lotion", kind: .treatment)
        s.products.append(lotion)
        s.plan.body = SlotPlan(enabled: true, time: ClockTime(20, 30), steps: [Step(productId: lotion.id)], anchor: Anchor(day: start, pos: 0), name: "Back")
        s.recordPlan(today: start)
        for d in 0..<4 { s.markDone(.body, on: start.adding(d), today: start.adding(4)) }
        s.editPlan(.body, today: start.adding(4)) { $0.plan.body.enabled = false }
        s.recordPlan(today: start.adding(4))
        // Off: the logged days stay.
        var tl = TreatmentTimeline.build(s, today: start.adding(8))
        var back = tl.rows.first { $0.slot == .body }!
        XCTAssertEqual((0..<4).map { back.marks[tl.index(start.adding($0))] }, Array(repeating: .activeDone, count: 4))
        XCTAssertTrue((4...8).allSatisfy { back.marks[tl.index(start.adding($0))] == .none })
        // On again: the days it was off aren't misses.
        s.editPlan(.body, today: start.adding(8)) { $0.plan.body.enabled = true }
        s.recordPlan(today: start.adding(8))
        tl = TreatmentTimeline.build(s, today: start.adding(8))
        back = tl.rows.first { $0.slot == .body }!
        XCTAssertTrue((4..<8).allSatisfy { back.marks[tl.index(start.adding($0))] == .none })
        XCTAssertEqual(back.marks[tl.index(start.adding(8))], .pending)
    }

    func testTimelineIsCappedAndStartsWithTheRoutine() {
        var s = base()
        let today = start.adding(200)
        let tl = TreatmentTimeline.build(s, today: today)
        XCTAssertEqual(tl.days, 98)
        XCTAssertEqual(tl.to, today)
        // A peel well before the routine is named as "earlier"; a photo in the two weeks before it is shown.
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(-40)), today: start)
        s.photos.append(PhotoMeta(day: start.adding(-5)))
        let short = TreatmentTimeline.build(s, today: start.adding(30))
        XCTAssertEqual(short.from, start.adding(-5))
        XCTAssertEqual(short.beforeDays, 5)
        XCTAssertEqual(short.earlier.map(\.name), ["Chemical peel"])
        XCTAssertTrue(short.procedures.isEmpty)
    }

    func testOralMedicationCountsAsTreatment() {
        var s = base()
        let doxy = Product(name: "Doxycycline 100 mg", kind: .oral)
        s.products.append(doxy)
        s.plan.am.steps.insert(Step(productId: doxy.id), at: 0)
        s.recordPlan(today: start)
        s.markDone(.am, on: start, today: start.adding(1))
        let tl = TreatmentTimeline.build(s, today: start.adding(1))
        XCTAssertEqual(tl.rows.first { $0.slot == .am }!.marks[tl.index(start)], .activeDone)
    }

    func testChangeNumbersAreTheSameEverywhere() {
        var s = base()
        for d in [2, 40, 90] {
            s.plan.pm.steps[tretStep(s)].amount = "Amount \(d)"
            s.recordPlan(today: start.adding(d))
        }
        let short = TreatmentTimeline.build(s, today: start.adding(95), maxDays: 50)
        XCTAssertEqual(short.changes.map(\.number), [3])
        let long = TreatmentTimeline.build(s, today: start.adding(95))
        XCTAssertEqual(long.changes.map(\.number), [1, 2, 3])
    }

    func testDemoHasAStory() {
        let today = Day(2026, 10, 21)
        let s = Presets.demoState(today: today)
        let changes = PlanHistory.changes(s)
        XCTAssertEqual(changes.map(\.lines), [
            ["Back routine started: Clindamycin lotion, every day"],
            ["Azelaic acid 15%: started, every morning"],
        ])
        XCTAssertTrue(Scores.isDue(s, area: .face, today: today))
        XCTAssertTrue(Scores.isDue(s, area: .body, today: today))
        let tl = TreatmentTimeline.build(s, today: today)
        XCTAssertEqual(tl.from, today.adding(-23), "starts with the routine")
        XCTAssertEqual(tl.beforeDays, 0)
        XCTAssertEqual(tl.earlier.map(\.name), ["Chemical peel"])
        XCTAssertEqual(tl.rows.map(\.slot), [.pm, .am, .body])
        XCTAssertEqual(tl.changes.map(\.number), [1, 2])
        XCTAssertEqual(tl.procedures.map(\.name), ["Subcision 1/3"])
        XCTAssertEqual(tl.breaks.first?.area, .face)
        // Mornings before the azelaic acid was added (day 12) were basics only.
        let am = tl.rows.first { $0.slot == .am }!
        XCTAssertFalse(am.marks[0..<12].contains(.activeDone))
        XCTAssertTrue(am.marks[12...].contains(.activeDone))
        // No back routine before day 9.
        let back = tl.rows.first { $0.slot == .body }!
        XCTAssertTrue(back.marks[0..<9].allSatisfy { $0 == .none })
    }
}
