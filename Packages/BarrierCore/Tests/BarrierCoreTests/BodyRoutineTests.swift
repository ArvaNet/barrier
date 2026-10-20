import XCTest
@testable import BarrierCore

final class BodyRoutineTests: XCTestCase {
    let start = Day(2026, 10, 5)
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        return c
    }()

    func withBack(_ s: AppState) -> AppState {
        var s = s
        let lotion = Product(name: "Clindamycin lotion", kind: .treatment)
        s.products.append(lotion)
        s.plan.body = SlotPlan(enabled: true, time: ClockTime(20, 30), steps: [Step(productId: lotion.id, amount: "Thin layer")],
                               anchor: Anchor(day: start, pos: 0), name: "Back", cue: "After shower")
        s.onboarded = true
        s.settings.photoDay = -1
        return s
    }

    func testOldSavesWithoutABodyRoutineStillLoad() throws {
        let s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        var json = String(data: try StateCoder.encode(s), encoding: .utf8)!
        // Strip the body key, as a save from before the body routine would look.
        let data = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        var plan = data["plan"] as! [String: Any]
        plan.removeValue(forKey: "body")
        var old = data
        old["plan"] = plan
        json = String(data: try JSONSerialization.data(withJSONObject: old), encoding: .utf8)!
        let back = try StateCoder.decode(Data(json.utf8))
        XCTAssertFalse(back.plan.body.enabled)
        XCTAssertEqual(back.plan.pm, s.plan.pm)
    }

    func testBodyRoutineKeepsItsOwnNameAndDoesNotTouchTheFace() {
        let s = withBack(Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start))
        let body = Engine.instance(s, slot: .body, on: start, today: start)
        XCTAssertEqual(body.label, "Back")
        XCTAssertEqual(body.hue, .lilac)
        XCTAssertEqual(body.steps.map(\.product.name), ["Clindamycin lotion"])
        // The face night is unchanged and has no cross-area conflict.
        let pm = Engine.instance(s, slot: .pm, on: start, today: start)
        XCTAssertEqual(pm.label, "Retinoid night")
        XCTAssertFalse(pm.steps.contains { $0.product.name == "Clindamycin lotion" })
    }

    func testBodyRemindersUseTheCue() {
        let s = withBack(Presets.apply(.simple, to: Presets.blankState(today: start), today: start))
        let noon = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        let r = Reminders.plan(s, now: noon, calendar: cal)
        let main = r.first { $0.id == "\(start.iso):body:main" }
        XCTAssertEqual(main?.title, "After shower: back")
        XCTAssertEqual(main?.body, "Clindamycin lotion: thin layer. Tap Done when it’s on.")
        XCTAssertNotNil(r.first { $0.id == "\(start.iso):body:nudge" })
        XCTAssertLessThanOrEqual(r.count, 58)
    }

    func testRecoveryOnTheBackDropsItsActiveOnly() {
        var s = withBack(Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start))
        s.setRecovery(start, .body, on: true)
        let body = Engine.instance(s, slot: .body, on: start, today: start)
        XCTAssertEqual(body.label, "Back, gentle")
        XCTAssertTrue(body.steps.isEmpty)
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: start, today: start).label, "Retinoid night")
    }

    func testCheckInsArePerArea() {
        var s = Presets.blankState(today: start)
        s.checkIn(start, feel: [.calm])
        s.checkIn(start, feel: [.breakout], area: .body)
        XCTAssertEqual(s.checkIn(on: start)?.feel, [.calm])
        XCTAssertEqual(s.checkIn(on: start, area: .body)?.feel, [.breakout])
        s.checkIn(start, feel: [], area: .body)
        XCTAssertNil(s.checkIn(on: start, area: .body))
        XCTAssertNotNil(s.checkIn(on: start))
    }

    func testTemplatesKeepTheBodyRoutineAndItsProducts() {
        var s = withBack(Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start))
        s = Presets.apply(.simple, to: s, today: start)
        XCTAssertTrue(s.plan.body.enabled)
        XCTAssertNotNil(s.product(s.plan.body.steps[0].productId))
        s.pruneOrphanProducts()
        XCTAssertNotNil(s.product(s.plan.body.steps[0].productId))
    }

    func testStatsAndRecapCountTheBody() {
        let monday = Day(2026, 11, 2)
        let s = Presets.demoState(today: monday)
        XCTAssertGreaterThan(Engine.stats(s, today: monday).bodyDone, 5)
        let r = Recaps.lastWeek(s, today: monday)
        XCTAssertEqual(r?.bodyName, "Back")
        XCTAssertEqual(r?.bodyDue, 7)
        XCTAssertTrue(r?.lines.contains { $0.hasPrefix("Back: ") } ?? false)
    }

    func testDescribeUsesDays() {
        var sp = Plan.defaultBody(start)
        sp.length = 2
        let step = Step(productId: "x", on: .nights([0]))
        XCTAssertEqual(Engine.describe(step, in: sp, slot: .body), "Every other day")
    }
}
