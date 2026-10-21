import XCTest
@testable import BarrierCore

final class ProcedureTests: XCTestCase {
    let start = Day(2026, 10, 5)
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        return c
    }()

    /// Tretinoin every other night, plus a back lotion every day.
    func base() -> AppState {
        var s = Presets.apply(.retinoid, to: Presets.blankState(today: start), today: start)
        s.plan.pm.easeIn = nil
        let lotion = Product(name: "Clindamycin lotion", kind: .treatment)
        s.products.append(lotion)
        s.plan.body = SlotPlan(enabled: true, time: ClockTime(20, 30), steps: [Step(productId: lotion.id)], anchor: Anchor(day: start, pos: 0), name: "Back")
        s.onboarded = true
        s.settings.photoDay = -1
        return s
    }

    func at(_ day: Day, _ h: Int, _ m: Int = 0) -> Date { DayTime(day, ClockTime(h, m)).date(calendar: cal) }

    // MARK: Model

    func testOldSavesWithoutProceduresStillLoad() throws {
        var s = base()
        s.pauses = [Pause(from: start, to: start.adding(2), reason: .travel)]
        let obj = try JSONSerialization.jsonObject(with: try StateCoder.encode(s)) as! [String: Any]
        var old = obj
        old.removeValue(forKey: "procedures")
        let back = try StateCoder.decode(try JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(back.procedures, [])
        XCTAssertEqual(back.pauses.count, 1)
        XCTAssertNil(back.pauses[0].area, "an old pause covers every routine")
    }

    func testOneBadProcedureDoesNotCostTheOthers() throws {
        var s = base()
        s.saveProcedure(Procedure(name: "Subcision", day: start.adding(3)), today: start)
        var obj = try JSONSerialization.jsonObject(with: try StateCoder.encode(s)) as! [String: Any]
        var list = obj["procedures"] as! [Any]
        list.append(["id": "broken"])
        obj["procedures"] = list
        let back = try StateCoder.decode(try JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(back.procedures.map(\.name), ["Subcision"])
    }

    func testTitles() {
        XCTAssertEqual(Procedure(name: "Subcision", day: start).title, "Subcision")
        XCTAssertEqual(Procedure(name: "Subcision", day: start, session: 2, sessions: 3).title, "Subcision, session 2 of 3")
        XCTAssertEqual(Procedure(name: "Subcision", day: start, session: 4, sessions: 3).title, "Subcision, session 4")
        XCTAssertEqual(Procedures.since(0), "Day of")
        XCTAssertEqual(Procedures.since(1), "1 day after")
        XCTAssertEqual(Procedures.since(13), "13 days after")
        XCTAssertEqual(Procedures.since(35), "5 weeks after")
        XCTAssertEqual(Procedures.since(200), "6 months after")
        XCTAssertTrue(Procedures.sunCare("Fractional CO2 laser"))
        XCTAssertTrue(Procedures.sunCare("TCA CROSS"))
        XCTAssertFalse(Procedures.sunCare("Botox"))
    }

    // MARK: Actives break

    func testABreakDropsFaceActivesButLeavesTheBackAlone() {
        var s = base()
        let day = start.adding(10)
        s.saveProcedure(Procedure(name: "Fractional CO2 laser", day: day, breakBefore: 3, breakAfter: 4), today: start)
        XCTAssertEqual(s.pauses.count, 1)
        XCTAssertEqual(s.pauses[0].from, day.adding(-3))
        XCTAssertEqual(s.pauses[0].to, day.adding(4))
        XCTAssertEqual(s.pauses[0].area, .face)
        for d in [day.adding(-3), day, day.adding(4)] {
            let pm = Engine.instance(s, slot: .pm, on: d, today: start)
            XCTAssertEqual(pm.rest, .pause)
            XCTAssertFalse(pm.steps.contains(where: \.active), "no retinoid during the break")
            XCTAssertNil(Engine.instance(s, slot: .body, on: d, today: start).rest, "a face procedure leaves the back routine on")
        }
        XCTAssertNotEqual(Engine.instance(s, slot: .pm, on: day.adding(5), today: start).rest, .pause)
        XCTAssertEqual(Procedures.breakFor(s, slot: .pm, on: day)?.name, "Fractional CO2 laser")
        XCTAssertNil(Procedures.breakFor(s, slot: .body, on: day))
    }

    func testABackProcedurePausesOnlyTheBack() {
        var s = base()
        s.saveProcedure(Procedure(name: "Cortisone injection", day: start.adding(2), area: .body, breakBefore: 0, breakAfter: 2), today: start)
        XCTAssertEqual(Engine.instance(s, slot: .body, on: start.adding(3), today: start).rest, .pause)
        XCTAssertNotEqual(Engine.instance(s, slot: .pm, on: start.adding(3), today: start).rest, .pause)
    }

    func testNoBreakUnlessTheClinicAskedForOne() {
        var s = base()
        s.saveProcedure(Procedure(name: "Subcision", day: start.adding(5)), today: start)
        XCTAssertTrue(s.pauses.isEmpty)
        // "0 days before, 0 after" is a break on the day itself.
        var p = s.procedures[0]
        p.breakBefore = 0
        p.breakAfter = 0
        s.saveProcedure(p, today: start)
        XCTAssertEqual(s.pauses.map(\.from), [start.adding(5)])
        XCTAssertEqual(s.pauses.map(\.to), [start.adding(5)])
    }

    func testMovingAProcedureMovesItsBreak() {
        var s = base()
        var p = Procedure(name: "Chemical peel", day: start.adding(10), breakBefore: 2, breakAfter: 2)
        s.saveProcedure(p, today: start)
        p.day = start.adding(20)
        s.saveProcedure(p, today: start)
        XCTAssertEqual(s.pauses.count, 1)
        XCTAssertEqual(s.pauses[0].from, start.adding(18))
        XCTAssertEqual(s.pauses[0].to, start.adding(22))
    }

    func testDaysAlreadyOnABreakStayThatWay() {
        var s = base()
        var p = Procedure(name: "Chemical peel", day: start.adding(5), breakBefore: 3, breakAfter: 3)
        s.saveProcedure(p, today: start)
        // Day 4: the break started on day 2. The clinic moves the peel to day 12.
        let today = start.adding(4)
        p.day = start.adding(12)
        s.saveProcedure(p, today: today)
        let ranges = s.pauses.filter { $0.procedureID == p.id }.map { [$0.from, $0.to] }.sorted { $0[0] < $1[0] }
        XCTAssertEqual(ranges, [[start.adding(2), start.adding(3)], [start.adding(9), start.adding(15)]])
        // Editing again with nothing changed doesn't touch anything.
        let before = s.pauses
        s.saveProcedure(p, today: today)
        XCTAssertEqual(Set(s.pauses), Set(before))
    }

    func testAnOngoingBreakStaysOnePause() {
        var s = base()
        let p = Procedure(name: "Microneedling", day: start.adding(5), breakBefore: 3, breakAfter: 3)
        s.saveProcedure(p, today: start)
        let id = s.pauses[0].id
        s.saveProcedure(p, today: start.adding(4))
        XCTAssertEqual(s.pauses.count, 1)
        XCTAssertEqual(s.pauses[0].id, id)
        XCTAssertEqual(s.pauses[0].from, start.adding(2))
        XCTAssertEqual(s.pauses[0].to, start.adding(8))
    }

    func testEndingTheBreakEarlyStaysEndedAfterAnEdit() {
        var s = base()
        let p = Procedure(name: "Chemical peel", day: start.adding(5), breakBefore: 2, breakAfter: 6)
        s.saveProcedure(p, today: start)
        let today = start.adding(8)
        s.endPause(s.pauses[0].id, today: today)
        XCTAssertEqual(s.pauses.count, 1)
        XCTAssertEqual(s.pauses[0].to, start.adding(7))
        XCTAssertEqual(s.procedures[0].breakAfter, 2)
        // Adding a note later must not bring the break back.
        var edited = s.procedures[0]
        edited.note = "Healed well"
        s.saveProcedure(edited, today: today)
        XCTAssertEqual(s.pauses.count, 1)
        XCTAssertEqual(s.pauses[0].to, start.adding(7))
        XCTAssertNotEqual(Engine.instance(s, slot: .pm, on: today, today: today).rest, .pause)
    }

    func testEndingABreakBeforeTheProcedureKeepsTheBreakAfter() {
        var s = base()
        let laser = Procedure(name: "Fractional CO2 laser", day: start.adding(5), breakBefore: 4, breakAfter: 3)
        s.saveProcedure(laser, today: start)
        let today = start.adding(3)
        s.endPause(s.pauses[0].id, today: today)
        XCTAssertEqual(s.procedures[0].breakBefore, 0)
        XCTAssertEqual(s.procedures[0].breakAfter, 3, "the clinic's days after stay")
        let spans = s.pauses.map { [$0.from, $0.to] }.sorted { $0[0] < $1[0] }
        XCTAssertEqual(spans, [[start.adding(1), start.adding(2)], [start.adding(5), start.adding(8)]])
        XCTAssertNotEqual(Engine.instance(s, slot: .pm, on: today, today: today).rest, .pause, "actives back on until the laser")
        XCTAssertEqual(Engine.instance(s, slot: .pm, on: laser.day, today: today).rest, .pause)
    }

    func testRemovingABreakThatHasNotStartedTurnsItOff() {
        var s = base()
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(5), breakBefore: 2, breakAfter: 3), today: start)
        s.endPause(s.pauses[0].id, today: start)
        XCTAssertNil(s.procedures[0].breakBefore)
        XCTAssertNil(s.procedures[0].breakAfter)
        XCTAssertTrue(s.pauses.isEmpty)
    }

    func testEndingOnTheProcedureDayEndsIt() {
        var s = base()
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(3), breakBefore: 2, breakAfter: 3), today: start)
        let today = start.adding(3)
        s.endPause(s.pauses[0].id, today: today)
        XCTAssertEqual(s.pauses.map(\.to), [start.adding(2)], "days already on the break stay in the history")
        XCTAssertNotEqual(Engine.instance(s, slot: .pm, on: today, today: today).rest, .pause)
    }

    func testRemovingAProcedureKeepsPastBreakDays() {
        var s = base()
        let p = Procedure(name: "IPL", day: start.adding(3), breakBefore: 2, breakAfter: 2)
        s.saveProcedure(p, today: start)
        s.dismiss("proc:\(p.id):after")
        s.removeProcedure(p.id, today: start.adding(4))
        XCTAssertTrue(s.procedures.isEmpty)
        XCTAssertEqual(s.pauses.count, 1)
        XCTAssertEqual(s.pauses[0].to, start.adding(3))
        XCTAssertNil(s.pauses[0].procedureID)
        XCTAssertFalse(s.dismissed.contains { $0.hasPrefix("proc:") })
        // A procedure entirely in the future leaves nothing behind.
        var t = base()
        t.saveProcedure(p, today: start)
        t.removeProcedure(p.id, today: start)
        XCTAssertTrue(t.pauses.isEmpty)
    }

    func testABreakHoldsTheRotationLikeAnyPause() {
        var s = base()
        s.plan.pm.length = 2
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(2), breakBefore: 1, breakAfter: 1), today: start)
        let tl = Engine.timeline(s, slot: .pm, from: start, to: start.adding(5), today: start)
        // Positions: day 0 = 0, day 1-3 paused (hold), day 4 continues from 1.
        XCTAssertEqual(tl.map(\.pos), [0, 1, 1, 1, 1, 0])
    }

    // MARK: Photos

    func testBeforeAndAfterPhotos() {
        var s = base()
        let p = Procedure(name: "Subcision", day: start.adding(10))
        s.saveProcedure(p, today: start)
        s.photos = [
            PhotoMeta(id: "old", day: start),
            PhotoMeta(id: "pre", day: start.adding(8)),
            PhotoMeta(id: "back", day: start.adding(9), area: .body),
            PhotoMeta(id: "post1", day: start.adding(20)),
            PhotoMeta(id: "post2", day: start.adding(40)),
        ]
        XCTAssertEqual(Procedures.beforePhoto(p, in: s)?.id, "pre")
        XCTAssertEqual(Procedures.afterPhoto(p, in: s)?.id, "post2")
        XCTAssertEqual(Procedures.recentBefore(p, in: s)?.id, "pre")
        // Photos on the day itself: with one from the week before, they're "day of", not the before.
        s.photos.append(PhotoMeta(id: "dayof-late", day: p.day, at: at(p.day, 18)))
        s.photos.append(PhotoMeta(id: "dayof", day: p.day, at: at(p.day, 8)))
        XCTAssertEqual(Procedures.beforePhoto(p, in: s)?.id, "pre")
        XCTAssertEqual(Procedures.context(s.photos.first { $0.id == "pre" }!, in: s), "Before Subcision")
        XCTAssertEqual(Procedures.context(s.photos.first { $0.id == "dayof-late" }!, in: s), "Day of Subcision")
        XCTAssertEqual(Procedures.context(s.photos.first { $0.id == "post1" }!, in: s), "10 days after Subcision")
        XCTAssertNil(Procedures.context(s.photos.first { $0.id == "back" }!, in: s), "a face procedure says nothing about back photos")
        // Nothing in the week before: the earliest photo of the day is the before.
        s.photos.removeAll { $0.id == "pre" }
        XCTAssertEqual(Procedures.beforePhoto(p, in: s)?.id, "dayof")
        XCTAssertEqual(Procedures.context(s.photos.first { $0.id == "dayof" }!, in: s), "Before Subcision")
    }

    func testTheEveningBeforeBeatsAPhotoAfterTheAppointment() {
        var s = base()
        let p = Procedure(name: "Subcision", day: start.adding(10))
        s.saveProcedure(p, today: start)
        // As the 6 PM reminder asks, then a photo of the fresh result that evening.
        s.photos = [
            PhotoMeta(id: "eve", day: p.day.adding(-1), at: at(p.day.adding(-1), 19)),
            PhotoMeta(id: "fresh", day: p.day, at: at(p.day, 20)),
        ]
        XCTAssertEqual(Procedures.beforePhoto(p, in: s)?.id, "eve")
        XCTAssertNil(Procedures.afterPhoto(p, in: s), "the day itself is never the after")
    }

    func testSameDayProceduresShareBeforeAndAfter() {
        var s = base()
        let sub = Procedure(name: "Subcision", day: start.adding(10), at: at(start, 9))
        let laser = Procedure(name: "Fractional CO2 laser", day: start.adding(10), at: at(start, 10))
        s.saveProcedure(sub, today: start)
        s.saveProcedure(laser, today: start)
        s.photos = [PhotoMeta(id: "b", day: start.adding(9)), PhotoMeta(id: "a", day: start.adding(40))]
        for p in [sub, laser] {
            XCTAssertEqual(Procedures.beforePhoto(p, in: s)?.id, "b")
            XCTAssertEqual(Procedures.afterPhoto(p, in: s)?.id, "a")
        }
    }

    func testAProcedureBreakWinsOverATravelPause() {
        var s = base()
        s.addPause(from: start, to: start.adding(6), reason: .travel)
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(3), breakBefore: 1, breakAfter: 1), today: start)
        XCTAssertEqual(Procedures.breakFor(s, slot: .pm, on: start.adding(3))?.name, "Chemical peel")
        XCTAssertNotNil(Procedures.bannerPause(s, today: start.adding(3))?.procedureID)
        XCTAssertNil(Procedures.bannerPause(s, today: start)?.procedureID, "the trip shows when only it covers today")
    }

    func testABackBreakWithoutABackRoutineShowsNoBanner() {
        var s = base()
        s.plan.body.enabled = false
        s.saveProcedure(Procedure(name: "Cortisone injection", day: start, area: .body, breakBefore: 0, breakAfter: 2), today: start)
        XCTAssertNil(Procedures.bannerPause(s, today: start))
    }

    func testScarAndSunNotes() {
        XCTAssertFalse(Procedures.sunCare("Subcision"), "no sourced sun advice for subcision")
        XCTAssertTrue(Procedures.scarTreatment("Subcision"))
        XCTAssertFalse(Procedures.sunCare("IPL"))
        XCTAssertFalse(Procedures.scarTreatment("Vascular laser"))
        XCTAssertTrue(Procedures.sunCare("Vascular laser"))
        XCTAssertEqual(Procedures.photoMark(4), "4 weeks")
        XCTAssertEqual(Procedures.photoMark(26), "6 months")
    }

    func testAfterPhotoStopsAtTheNextSession() {
        var s = base()
        let one = Procedure(name: "Subcision", day: start.adding(10), session: 1, sessions: 2)
        let two = Procedure(name: "Subcision", day: start.adding(40), session: 2, sessions: 2)
        s.saveProcedure(one, today: start)
        s.saveProcedure(two, today: start)
        s.photos = [
            PhotoMeta(id: "a", day: start.adding(9)),
            PhotoMeta(id: "b", day: start.adding(38)),
            PhotoMeta(id: "c", day: start.adding(70)),
        ]
        XCTAssertEqual(Procedures.afterPhoto(one, in: s)?.id, "b", "session 1's after is session 2's before")
        XCTAssertEqual(Procedures.beforePhoto(two, in: s)?.id, "b")
        XCTAssertEqual(Procedures.afterPhoto(two, in: s)?.id, "c")
        XCTAssertEqual(Procedures.series(two, in: s).map(\.id), [one.id, two.id])
        // No photo between the sessions: session 1 has no after.
        s.photos.removeAll { $0.id == "b" }
        XCTAssertNil(Procedures.afterPhoto(one, in: s))
    }

    // MARK: Today

    func testTodayMoments() {
        var s = base()
        let p = Procedure(name: "Subcision", day: start.adding(10))
        s.saveProcedure(p, today: start)
        XCTAssertTrue(Procedures.moments(s, today: start).isEmpty, "more than a week out: nothing on Today")
        XCTAssertEqual(Procedures.moments(s, today: start.adding(4)), [.upcoming(s.procedures[0], inDays: 6)])
        XCTAssertEqual(Procedures.moments(s, today: start.adding(10)), [.upcoming(s.procedures[0], inDays: 0)])
        XCTAssertEqual(Procedures.moments(s, today: start.adding(13)), [.after(s.procedures[0], day: 3)])
        XCTAssertTrue(Procedures.moments(s, today: start.adding(25)).isEmpty, "the after card goes after two weeks")
        // Four weeks on, no photo since: ask for one.
        let w4 = start.adding(10 + 28)
        XCTAssertEqual(Procedures.moments(s, today: w4), [.photo(s.procedures[0], weeks: 4)])
        s.photos.append(PhotoMeta(day: w4))
        XCTAssertTrue(Procedures.moments(s, today: w4.adding(1)).isEmpty, "a photo since the 4-week mark answers it")
        // Twelve weeks: asked again.
        XCTAssertEqual(Procedures.moments(s, today: start.adding(10 + 84)), [.photo(s.procedures[0], weeks: 12)])
        // Hiding sticks.
        s.dismiss(ProcedureMoment.photo(s.procedures[0], weeks: 12).dismissID!)
        XCTAssertTrue(Procedures.moments(s, today: start.adding(10 + 85)).isEmpty)
    }

    func testTomorrowComesBeforeRecovery() {
        var s = base()
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(2)), today: start)
        s.saveProcedure(Procedure(name: "Cortisone injection", day: start.adding(6), area: .body), today: start)
        s.saveProcedure(Procedure(name: "Filler", day: start.adding(10)), today: start)
        let m = Procedures.moments(s, today: start.adding(5))
        XCTAssertEqual(m.map(\.procedure.name), ["Cortisone injection", "Chemical peel", "Filler"])
    }

    func testIsotretinoinIsNoticed() {
        var s = base()
        XCTAssertFalse(Procedures.takesIsotretinoin(s))
        s.products.append(Product(name: "Roaccutane 20 mg", kind: .oral))
        XCTAssertTrue(Procedures.takesIsotretinoin(s))
    }

    // MARK: Reminders

    func testEveningBeforeReminder() {
        var s = base()
        let p = Procedure(name: "Subcision", day: start.adding(5))
        s.saveProcedure(p, today: start)
        let plan = Reminders.plan(s, now: at(start, 9), calendar: cal)
        let r = plan.first { $0.id.contains(":proc:") }
        XCTAssertEqual(r?.title, "Subcision tomorrow")
        XCTAssertEqual(r?.fire, DayTime(start.adding(4), ClockTime(18, 0)))
        XCTAssertEqual(r?.actionable, false)
        XCTAssertTrue(r?.body.contains("before photo") == true)
        // With a recent before photo, it says so.
        s.photos.append(PhotoMeta(day: start.adding(3)))
        let again = Reminders.plan(s, now: at(start, 9), calendar: cal).first { $0.id.contains(":proc:") }
        XCTAssertTrue(again?.body.hasPrefix("Your before photo is ready") == true)
    }

    func testBreakNightsSayWhy() {
        var s = base()
        s.saveProcedure(Procedure(name: "Chemical peel", day: start.adding(1), breakBefore: 1, breakAfter: 1), today: start)
        let plan = Reminders.plan(s, now: at(start, 9), calendar: cal)
        let tonight = plan.first { $0.id == "\(start.iso):pm:main" }
        XCTAssertEqual(tonight?.title, "Simple night")
        XCTAssertTrue(tonight?.body.hasPrefix("Actives break (Chemical peel)") == true)
        XCTAssertFalse(tonight?.body.contains("Tretinoin") == true)
        // The back routine isn't on the break.
        let back = plan.first { $0.id == "\(start.iso):body:main" }
        XCTAssertFalse(back?.body.contains("break") == true)
    }

    func testAfterPhotoReminderAtFourWeeks() {
        var s = base()
        let p = Procedure(name: "Microneedling", day: start)
        s.saveProcedure(p, today: start)
        let now = at(start.adding(20), 9)
        let r = Reminders.plan(s, now: now, calendar: cal).first { $0.id.contains(":procphoto:") }
        XCTAssertEqual(r?.title, "4 weeks since Microneedling")
        XCTAssertEqual(r?.fire, DayTime(start.adding(28), ClockTime(12, 0)))
        // A photo already taken that day: no reminder.
        var taken = s
        taken.photos.append(PhotoMeta(day: start.adding(28), at: at(start.adding(28), 8)))
        XCTAssertNil(Reminders.plan(taken, now: at(start.adding(28), 9), calendar: cal).first { $0.id.contains(":procphoto:") })
        // Hidden on Today: no reminder either.
        s.dismiss("proc:\(p.id):w4")
        XCTAssertNil(Reminders.plan(s, now: now, calendar: cal).first { $0.id.contains(":procphoto:") })
    }

    func testOneOffsSurviveTheCapAndKeepAliveComesFirst() {
        var s = base()
        // Morning, evening, body and sunscreen fill the plan past the cap.
        let spf = Product(name: "SPF 50", kind: .spf)
        s.products.append(spf)
        s.plan.am.enabled = true
        s.plan.am.steps.append(Step(productId: spf.id))
        s.settings.spfMidday = true
        s.plan.followUp = FollowUp(day: start.adding(12))
        s.saveProcedure(Procedure(name: "Subcision", day: start.adding(13)), today: start)
        let plan = Reminders.plan(s, now: at(start, 5), calendar: cal)
        XCTAssertLessThanOrEqual(plan.count, 58)
        XCTAssertTrue(plan.contains { $0.kind == .followUp })
        XCTAssertTrue(plan.contains { $0.kind == .procedure })
        let keep = plan.first { $0.kind == .keepAlive }
        XCTAssertNotNil(keep)
        // The keep-alive fires no later than the last routine reminder that made it in.
        let lastRoutine = plan.filter { $0.kind == .main || $0.kind == .nudge || $0.kind == .spf }.map { $0.fire.date(calendar: cal) }.max()!
        XCTAssertLessThanOrEqual(keep!.fire.date(calendar: cal), lastRoutine)
    }

    func testDemoTellsTheStory() {
        let today = Day(2026, 10, 21)
        let s = Presets.demoState(today: today)
        let sub = s.procedures.first { $0.id == "demo-sub-1" }!
        XCTAssertEqual(Procedures.moments(s, today: today).first, .after(sub, day: 6))
        XCTAssertNotEqual(Engine.instance(s, slot: .pm, on: today, today: today).rest, .pause, "the break ended yesterday")
        let peel = s.procedures.first { $0.id == "demo-peel" }!
        XCTAssertEqual(Procedures.beforePhoto(peel, in: s)?.id, "demo-face-0")
        XCTAssertEqual(Procedures.afterPhoto(peel, in: s)?.id, "demo-face-2")
        XCTAssertNil(Procedures.afterPhoto(sub, in: s), "no photo since the subcision yet")
        XCTAssertEqual(s.pauses.filter { $0.procedureID != nil }.count, 2)
    }
}
