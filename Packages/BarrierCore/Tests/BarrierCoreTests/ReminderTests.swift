import XCTest
@testable import BarrierCore

final class ReminderTests: XCTestCase {
    let start = Day(2026, 10, 5)
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        return c
    }()

    func at(_ d: Day, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: h, minute: m))!
    }

    func state(_ t: Presets.Template) -> AppState {
        var s = Presets.apply(t, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        s.settings.photoDay = -1
        return s
    }

    func testPlansMainsAndNudgesWithinTheLimit() {
        let s = state(.cycling)
        let r = Reminders.plan(s, now: at(start, 12), calendar: cal)
        let first = r.filter { $0.day == start && $0.slot != nil }
        XCTAssertEqual(first.map(\.kind), [.main, .nudge])
        XCTAssertEqual(first[0].title, "Tonight: Exfoliation night")
        XCTAssertTrue(first[0].body.contains("Exfoliant (AHA/BHA)"))
        XCTAssertEqual(r.filter { $0.kind == .main }.count, 14 + 13)
        XCTAssertEqual(r.filter { $0.kind == .nudge }.count, 2 + 3) // today pm + next 2 days am/pm…
        XCTAssertLessThanOrEqual(r.count, 60)
        XCTAssertNotNil(r.first { $0.kind == .keepAlive })
        // Far-off nights get generic text.
        XCTAssertEqual(r.first { $0.id == "\(start.adding(5).iso):pm:main" }?.title, "Evening routine")
    }

    func testDoneTonightDropsTonightsReminders() {
        var s = state(.cycling)
        s.log = [Entry(day: start, slot: .pm, status: .done)]
        let r = Reminders.plan(s, now: at(start, 21), calendar: cal)
        XCTAssertFalse(r.contains { $0.day == start && $0.slot == .pm })
        XCTAssertEqual(r.first { $0.id == "\(start.adding(1).iso):pm:main" }?.title, "Tonight: Retinoid night")
    }

    func testPhotoNightAndFollowUp() {
        var s = state(.simple)
        s.settings.photoDay = 2 // Tuesday
        s.plan.followUp = FollowUp(day: start.adding(7), with: "Dr. Jonaitis")
        s.questions = [Question(text: "Vitamin C?")]
        let r = Reminders.plan(s, now: at(start, 12), calendar: cal)
        XCTAssertEqual(r.first { $0.id == "\(start.adding(1).iso):pm:main" }?.title, "Tonight: Recovery night · photo night")
        let fu = r.first { $0.kind == .followUp }
        XCTAssertEqual(fu?.title, "Dr. Jonaitis tomorrow")
        XCTAssertTrue(fu?.body.contains("1 question") ?? false)
        XCTAssertEqual(fu?.fire.day, start.adding(6))
    }

    func testRemindersOffOrNotOnboarded() {
        var s = state(.simple)
        s.settings.remindersOn = false
        XCTAssertTrue(Reminders.plan(s, now: at(start, 12), calendar: cal).isEmpty)
    }

    func testRetinoidNightBodyUsesAmount() {
        let s = state(.retinoid)
        let r = Reminders.plan(s, now: at(start, 12), calendar: cal)
        XCTAssertEqual(r.first { $0.kind == .main && $0.slot == .pm }?.body, "Tretinoin: pea-size for the whole face. Tap to start.")
    }
}
