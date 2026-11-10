import XCTest
@testable import BarrierCore

final class BuildUpTests: XCTestCase {
    let start = Day(2026, 10, 5)

    /// Cleanser, adapalene every night, moisturizer. No build-up.
    func nightly(_ day: Day? = nil) -> AppState {
        let d = day ?? start
        var s = Presets.blankState(today: d)
        let c = Presets.makeProduct(name: "Gentle cleanser", kind: .cleanser, today: d)
        let a = Presets.makeProduct(name: "Adapalene", kind: .retinoid, today: d)
        let m = Presets.makeProduct(name: "Moisturizer", kind: .moisturizer, today: d)
        s.products = [c, a, m]
        s.plan.pm.steps = [Step(productId: c.id), Step(productId: a.id), Step(productId: m.id)]
        s.onboarded = true
        return s
    }

    func adapalene(_ s: AppState) -> Step { s.plan.pm.steps.first { s.product($0.productId)?.name == "Adapalene" }! }

    /// Which of the next `n` nights have adapalene, from `from`.
    func pattern(_ s: AppState, from: Day, _ n: Int, today: Day? = nil) -> [Bool] {
        let id = adapalene(s).id
        return Engine.timeline(s, slot: .pm, from: from, to: from.adding(n - 1), today: today ?? from)
            .map { inst in inst.steps.contains { $0.step.id == id } }
    }

    func done(_ s: inout AppState, _ d: Day, today: Day) {
        s.markDone(Engine.instance(s, slot: .pm, on: d, today: today))
    }

    func testRetinoidTemplateStartsEveryThirdNightTonight() {
        let s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        let tret = s.plan.pm.steps.first { s.product($0.productId)?.kind == .retinoid }!
        XCTAssertEqual(tret.buildUp?.stages, Presets.buildUpStages)
        XCTAssertEqual(tret.buildUp?.goal, 1)
        XCTAssertNil(s.plan.pm.easeIn)
        let id = tret.id
        let on = Engine.timeline(s, slot: .pm, from: start, to: start.adding(5), today: start).map { $0.steps.contains { $0.step.id == id } }
        XCTAssertEqual(on, [true, false, false, true, false, false])
    }

    func testStartBuildUpMakesTheScheduleTheGoal() {
        var s = nightly()
        XCTAssertTrue(s.startBuildUp(.pm, stepID: adapalene(s).id, stages: Presets.buildUpStages, start: start, today: start))
        XCTAssertEqual(adapalene(s).buildUp?.goal, 1)
        XCTAssertEqual(adapalene(s).buildUp?.every, 3)
        XCTAssertEqual(pattern(s, from: start, 6), [true, false, false, true, false, false])
        XCTAssertEqual(s.plan.pm.length, 3)
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: start.adding(1), today: start).label, "Recovery night")
    }

    func testStartingSlowlyAfterLastNightWaits() {
        var s = nightly()
        done(&s, start, today: start) // adapalene last night
        let today = start.adding(1)
        s.startBuildUp(.pm, stepID: adapalene(s).id, stages: Presets.buildUpStages, start: today, today: today)
        // Every 3rd night counted from last night: tonight and tomorrow off, then on.
        XCTAssertEqual(pattern(s, from: today, 5), [false, false, true, false, false])
    }

    func testSkippedBuildUpNightRepeats() {
        var s = nightly()
        s.startBuildUp(.pm, stepID: adapalene(s).id, stages: Presets.buildUpStages, start: start, today: start)
        s.markSkipped(Engine.instance(s, slot: .pm, on: start, today: start))
        // The adapalene night waits for you.
        XCTAssertEqual(pattern(s, from: start.adding(1), 4, today: start.adding(1)), [true, false, false, true])
    }

    func testAskWhenTheStageIsUpThenMoveUp() {
        var s = nightly()
        let id = adapalene(s).id
        s.startBuildUp(.pm, stepID: id, stages: Presets.buildUpStages, start: start, today: start)
        XCTAssertTrue(BuildUps.asks(s, today: start.adding(13)).isEmpty)
        let day = start.adding(14)
        let ask = BuildUps.asks(s, today: day)
        XCTAssertEqual(ask.count, 1)
        XCTAssertEqual(ask.first?.from, 3)
        XCTAssertEqual(ask.first?.to, 2)
        XCTAssertEqual(ask.first?.weeks, 2)

        // Done every adapalene night so far: days 0, 3, 6, 9, 12.
        for d in stride(from: 0, through: 12, by: 3) { done(&s, start.adding(d), today: start.adding(d)) }
        XCTAssertTrue(s.moveUp(.pm, stepID: id, today: day))
        XCTAssertEqual(adapalene(s).buildUp?.moves, [day])
        XCTAssertEqual(adapalene(s).buildUp?.every, 2)
        XCTAssertEqual(s.plan.pm.length, 2)
        // Last on day 12, so day 14 is due; then every other night.
        XCTAssertEqual(pattern(s, from: day, 5, today: day), [true, false, true, false, true])
        XCTAssertTrue(BuildUps.asks(s, today: day).isEmpty)

        // Second stage up: every night, the goal. The build-up stays as a record.
        let later = day.adding(14)
        XCTAssertEqual(BuildUps.asks(s, today: later).first?.to, 1)
        s.moveUp(.pm, stepID: id, today: later)
        XCTAssertEqual(adapalene(s).on, .all)
        XCTAssertEqual(adapalene(s).buildUp?.done, true)
        XCTAssertEqual(adapalene(s).buildUp?.finished, later)
        XCTAssertEqual(s.plan.pm.length, 1)
    }

    func testNotYetAsksAgainInAWeek() {
        var s = nightly()
        let id = adapalene(s).id
        s.startBuildUp(.pm, stepID: id, stages: Presets.buildUpStages, start: start, today: start)
        let day = start.adding(16) // answered two days late
        s.notYet(.pm, stepID: id, today: day)
        XCTAssertTrue(BuildUps.asks(s, today: day.adding(6)).isEmpty)
        XCTAssertEqual(BuildUps.asks(s, today: day.adding(7)).count, 1)
        XCTAssertEqual(adapalene(s).buildUp?.every, 3)
    }

    func testEndBuildUpGoesToTheGoal() {
        var s = nightly()
        let id = adapalene(s).id
        s.startBuildUp(.pm, stepID: id, stages: Presets.buildUpStages, start: start, today: start)
        s.endBuildUp(.pm, stepID: id, today: start.adding(2))
        XCTAssertNil(adapalene(s).buildUp)
        XCTAssertEqual(adapalene(s).on, .all)
        XCTAssertEqual(s.plan.pm.length, 1)
    }

    func testCompactKeepsOtherPatterns() {
        var sp = nightly().plan.pm
        sp.length = 6
        sp.steps[0].on = .nights([0, 2, 4])
        XCTAssertEqual(Engine.compact(sp).length, 2)
        XCTAssertEqual(Engine.compact(sp).steps[0].on, .nights([0]))
        sp.steps[0].on = .nights([0, 3])
        XCTAssertEqual(Engine.compact(sp).length, 3)
        sp.steps[0].on = .nights([0, 1, 3])
        XCTAssertEqual(Engine.compact(sp).length, 6)
    }

    // MARK: Old saves

    /// A routine eased in the old way: the whole evening, "+2 recovery nights", then "+1".
    func legacy(easedSince since: Day, today: Day) -> AppState {
        var s = nightly(since)
        s.plan.pm.easeIn = EaseIn(start: since, phases: Presets.easeInPhases)
        s.recordPlan(today: since)
        var d = since
        while d < today {
            done(&s, d, today: d)
            d = d.adding(1)
        }
        return s
    }

    func testOldEaseInBecomesABuildUpOnTheProduct() {
        let since = Day(2026, 10, 8)
        let today = Day(2026, 10, 27) // day 19: second phase, "+1"
        var s = legacy(easedSince: since, today: today)
        let before = pattern(s, from: today, 8, today: today)
        XCTAssertTrue(s.migrateEaseIn(today: today))
        XCTAssertNil(s.plan.pm.easeIn)
        let b = adapalene(s).buildUp
        XCTAssertEqual(b?.start, since)
        XCTAssertEqual(b?.stages, [BuildStage(every: 3, days: 14), BuildStage(every: 2, days: 14)])
        XCTAssertEqual(b?.moves, [Day(2026, 10, 22)])
        XCTAssertEqual(b?.goal, 1)
        // Tonight and the nights after are what they were.
        XCTAssertEqual(pattern(s, from: today, 8, today: today), before)
        XCTAssertFalse(s.migrateEaseIn(today: today))

        // The change log doesn't call it a removal.
        s.recordPlan(today: today)
        let lines = PlanHistory.changes(s).flatMap(\.lines)
        XCTAssertFalse(lines.contains { $0.contains("ease-in removed") }, "\(lines)")
    }

    func testOldEaseInInItsFirstPhaseKeepsTonight() {
        let since = Day(2026, 10, 20)
        for offset in 0..<3 {
            let today = since.adding(4 + offset)
            var s = legacy(easedSince: since, today: today)
            // Up to the end of the stage: after that, the old ease-in moved on by itself; now Tendwell asks.
            let before = pattern(s, from: today, 8, today: today)
            s.migrateEaseIn(today: today)
            XCTAssertEqual(adapalene(s).buildUp?.every, 3)
            XCTAssertEqual(pattern(s, from: today, 8, today: today), before, "offset \(offset)")
        }
    }

    func testFinishedOldEaseInJustGoes() {
        let since = Day(2026, 9, 1)
        let today = Day(2026, 10, 27)
        var s = legacy(easedSince: since, today: today)
        s.migrateEaseIn(today: today)
        XCTAssertNil(s.plan.pm.easeIn)
        XCTAssertEqual(adapalene(s).buildUp?.done, true)
        XCTAssertEqual(adapalene(s).on, .all)
        XCTAssertEqual(pattern(s, from: today, 3, today: today), [true, true, true])
    }

    // MARK: Change log

    func testMovesAreDatedInTheChangeLog() {
        var s = nightly()
        s.recordPlan(today: start)
        let id = adapalene(s).id
        let d1 = start.adding(1)
        s.startBuildUp(.pm, stepID: id, stages: Presets.buildUpStages, start: d1, today: d1)
        s.recordPlan(today: d1)
        let d2 = d1.adding(14)
        s.moveUp(.pm, stepID: id, today: d2)
        s.recordPlan(today: d2)
        let d3 = d2.adding(14)
        s.moveUp(.pm, stepID: id, today: d3)
        s.recordPlan(today: d3)
        let changes = PlanHistory.changes(s)
        XCTAssertEqual(changes.map(\.day), [d1, d2, d3])
        XCTAssertEqual(changes[0].lines, ["Adapalene: starting slowly, every 3rd night, building up to every night"])
        XCTAssertEqual(changes[1].lines, ["Adapalene: moved up to every other night, building up to every night"])
        XCTAssertEqual(changes[2].lines, ["Adapalene: now every night, build-up done"])
    }

    func testOldSavesWithoutBuildUpsStillLoad() throws {
        let s = nightly()
        var json = try JSONSerialization.jsonObject(with: StateCoder.encode(s)) as! [String: Any]
        var plan = json["plan"] as! [String: Any]
        var pm = plan["pm"] as! [String: Any]
        pm["steps"] = (pm["steps"] as! [[String: Any]]).map { var st = $0; st.removeValue(forKey: "buildUp"); return st }
        plan["pm"] = pm
        json["plan"] = plan
        let back = try StateCoder.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(back.plan.pm.steps.count, 3)
        XCTAssertNil(back.plan.pm.steps[1].buildUp)
    }
}

final class InsertOrderTests: XCTestCase {
    func testNewStepsKeepAHandMadeOrder() {
        let c = Step(productId: "c"), m = Step(productId: "m"), r = Step(productId: "r"), x = Step(productId: "x")
        let kinds: [String: ProductKind] = ["c": .cleanser, "m": .moisturizer, "r": .retinoid, "x": .retinoid]
        // Normal order: the retinoid goes between cleanser and moisturizer.
        XCTAssertEqual(Presets.insert(r, kind: .retinoid, into: [c, m], kinds: kinds).map(\.productId), ["c", "r", "m"])
        // Moisturizer dragged first: a new retinoid goes after the cleanser, not to the top.
        XCTAssertEqual(Presets.insert(x, kind: .retinoid, into: [m, c, r], kinds: kinds).map(\.productId), ["m", "c", "r", "x"])
        // A cleanser into a list of later things goes first.
        XCTAssertEqual(Presets.insert(c, kind: .cleanser, into: [r, m], kinds: kinds).map(\.productId), ["c", "r", "m"])
        XCTAssertEqual(Presets.insert(m, kind: .moisturizer, into: [], kinds: kinds).map(\.productId), ["m"])
    }
}
