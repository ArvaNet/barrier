import XCTest
@testable import BarrierCore

/// A body wash and moisturizer after the shower, and a back cream before bed.
final class TwoBodyRoutineTests: XCTestCase {
    let start = Day(2026, 10, 5)

    func twoRoutines() -> AppState {
        var s = Presets.blankState(today: start)
        let wash = Product(name: "Gentle body wash", kind: .cleanser)
        let lotion = Product(name: "Body moisturizer", kind: .moisturizer)
        let cream = Product(name: "Adapalene 0.1%", kind: .retinoid)
        s.products = [wash, lotion, cream]
        s.plan.body = SlotPlan(enabled: true, time: ClockTime(8, 30), steps: [Step(productId: wash.id), Step(productId: lotion.id)],
                               anchor: Anchor(day: start, pos: 0), name: "Body", cue: "After shower")
        s.plan.body2 = SlotPlan(enabled: true, time: ClockTime(22, 30), steps: [Step(productId: cream.id)],
                                anchor: Anchor(day: start, pos: 0), name: "Back", cue: "Before bed")
        s.onboarded = true
        s.settings.photoDay = -1
        return s
    }

    func testOldSavesWithoutASecondBodyRoutineLoadWithItOff() throws {
        let s = twoRoutines()
        var json = try JSONSerialization.jsonObject(with: StateCoder.encode(s)) as! [String: Any]
        var plan = json["plan"] as! [String: Any]
        plan.removeValue(forKey: "body2")
        json["plan"] = plan
        let back = try StateCoder.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(back.plan.body2.enabled)
        XCTAssertEqual(back.plan.body2.cue, "Before bed")
        XCTAssertEqual(back.plan.body, s.plan.body)
    }

    func testEachRoutineIsLoggedOnItsOwn() {
        var s = twoRoutines()
        s.markDone(Engine.instance(s, slot: .body, on: start, today: start))
        XCTAssertEqual(Engine.instance(s, slot: .body, on: start, today: start).status, .done)
        XCTAssertEqual(Engine.instance(s, slot: .body2, on: start, today: start).status, .pending)
        XCTAssertEqual(Engine.instance(s, slot: .body2, on: start, today: start).steps.map(\.product.name), ["Adapalene 0.1%"])
        XCTAssertEqual(Engine.stats(s, today: start).bodyDone, 1)
        XCTAssertEqual(Slot.body2.area, .body)
    }

    func testTabsUseTheMomentWhenThereAreTwo() {
        var s = twoRoutines()
        XCTAssertEqual(s.plan.shortName(.body), "After shower")
        XCTAssertEqual(s.plan.shortName(.body2), "Before bed")
        s.plan.body2.enabled = false
        XCTAssertEqual(s.plan.shortName(.body), "Body")
    }

    func testEachGetsItsOwnReminder() {
        let s = twoRoutines()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7))!
        let mains = Reminders.plan(s, now: now, calendar: cal).filter { $0.kind == .main && $0.day == start }
        XCTAssertEqual(Set(mains.map(\.slot)), [.body, .body2])
        XCTAssertTrue(mains.first { $0.slot == .body2 }!.title.contains("Before bed"), mains.map(\.title).description)
    }

    func testTheChangeLogNamesTheSecondRoutine() {
        var s = twoRoutines()
        s.plan.body2.enabled = false
        s.recordPlan(today: start)
        s.plan.body2.enabled = true
        s.recordPlan(today: start.adding(1))
        let lines = PlanHistory.changes(s).flatMap(\.lines)
        XCTAssertEqual(lines.count, 1, lines.description)
        XCTAssertTrue(lines[0].hasPrefix("Before bed routine started"), lines[0])
    }
}
