import XCTest
@testable import BarrierCore

/// A routine handed over by a clinic as a QR code: the text form, its rules, and what loading it does.
final class PlanCodeTests: XCTestCase {
    let today = Day(2026, 11, 10)

    /// Tretinoin easing in with a wait after cleansing, azelaic acid and a 12-week course in the morning.
    func retinoidCode() throws -> PlanCode {
        try PlanCode(
            clinic: "Dr. Petrauskienė",
            products: [
                .init(name: "Gentle cleanser", kind: .cleanser),
                .init(name: "Tretinoin 0.025% cream", kind: .retinoid, note: "Avoid the corners of the nose and mouth."),
                .init(name: "Moisturizer", kind: .moisturizer),
                .init(name: "Azelaic acid 15%", kind: .treatment),
                .init(name: "Sunscreen SPF 30+", kind: .spf),
                .init(name: "Doxycycline 40 mg", kind: .oral, note: "With food and a full glass of water.", courseDays: 84),
            ],
            routines: [
                .pm: .init(steps: [.init(product: 0, waitMin: 20), .init(product: 1, amount: "Pea-size", how: "On completely dry skin"), .init(product: 2)],
                           easeIn: [EaseInPhase(days: 14, extraRest: 2), EaseInPhase(days: 14, extraRest: 1)]),
                .am: .init(steps: [.init(product: 5), .init(product: 0), .init(product: 3, amount: "Thin layer"), .init(product: 2), .init(product: 4)]),
            ],
            ifIrritated: "Skip tretinoin for 2 nights, moisturizer only, then restart every other night.")
    }

    /// Skin cycling: exfoliant on night 1, retinol on night 2, two recovery nights.
    func cyclingCode() throws -> PlanCode {
        try PlanCode(
            products: [
                .init(name: "Cleanser", kind: .cleanser),
                .init(name: "Glycolic acid 7%", kind: .exfoliant),
                .init(name: "Retinol serum", kind: .retinoid),
                .init(name: "Moisturizer", kind: .moisturizer),
            ],
            routines: [.pm: .init(length: 4, steps: [.init(product: 0), .init(product: 1, on: .nights([0])), .init(product: 2, on: .nights([1])), .init(product: 3)])])
    }

    func backCode() throws -> PlanCode {
        try PlanCode(
            products: [.init(name: "Benzoyl peroxide wash 5%", kind: .treatment, note: "Leave on two minutes, then rinse.")],
            routines: [.body: .init(steps: [.init(product: 0, on: .weekdays([1, 3, 5]))], name: "Back", cue: "After shower")])
    }

    func link(_ json: String) -> String {
        PlanCode.linkPrefix + Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func assertInvalid(_ json: String, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PlanCode(link: link(json)), file: file, line: line) { error in
            guard case PlanCodeError.invalid(let message) = error else { return XCTFail("expected invalid, got \(error)", file: file, line: line) }
            XCTAssertTrue(message.contains(why), "\"\(message)\" doesn't mention \"\(why)\"", file: file, line: line)
        }
    }

    func onboarded(_ template: Presets.Template, since start: Day) -> AppState {
        var s = Presets.apply(template, to: Presets.blankState(today: start), today: start)
        s.onboarded = true
        s.settings.photoDay = -1
        s.recordPlan(today: start)
        return s
    }

    // MARK: The text form

    func testACodeSurvivesTheTripThroughItsLink() throws {
        for code in [try retinoidCode(), try cyclingCode(), try backCode()] {
            XCTAssertTrue(code.link.hasPrefix("barrier://plan/"))
            XCTAssertEqual(try PlanCode(link: code.link), code)
        }
    }

    func testTheFormatIsLocked() throws {
        // Printed codes live for years. If this fails, the format changed: bump the version instead.
        let payload = "eyJwIjpbeyJrIjoicmV0aW5vaWQiLCJuIjoiVHJldGlub2luIn1dLCJwbSI6eyJzIjpbeyJwIjowfV19LCJ2IjoxfQ"
        let code = try PlanCode(products: [.init(name: "Tretinoin", kind: .retinoid)], routines: [.pm: .init(steps: [.init(product: 0)])])
        XCTAssertEqual(code.payload, payload)
        XCTAssertEqual(try PlanCode(link: "barrier://plan/" + payload), code)

        // Every key, written by hand the way the clinic page writes it.
        let full = """
        {"v":1,"c":"Dr. Petrauskienė","i":"Stop for two nights.","p":[{"n":"Cleanser","k":"cleanser"},{"n":"Tretinoin 0.025% cream","k":"retinoid","o":"Avoid the eyes."},\
        {"n":"Antibiotic","k":"oral","d":84},{"n":"Lotion","k":"treatment"}],\
        "pm":{"l":2,"s":[{"p":0,"w":20},{"p":1,"a":"Pea-size","h":"On dry skin","n":[0]}],"e":[[14,1]]},\
        "am":{"s":[{"p":2,"d":[1,3,5]},{"p":0}]},"body":{"s":[{"p":3}],"n":"Back","q":"After shower"}}
        """
        let read = try PlanCode(link: link(full))
        XCTAssertEqual(read.clinic, "Dr. Petrauskienė")
        XCTAssertEqual(read.ifIrritated, "Stop for two nights.")
        XCTAssertEqual(read.products.map(\.kind), [.cleanser, .retinoid, .oral, .treatment])
        XCTAssertEqual(read.products[1].note, "Avoid the eyes.")
        XCTAssertEqual(read.products[2].courseDays, 84)
        XCTAssertEqual(read.slots, [.am, .pm, .body])
        let pm = try XCTUnwrap(read.routines[.pm])
        XCTAssertEqual(pm.length, 2)
        XCTAssertEqual(pm.steps[0].waitMin, 20)
        XCTAssertEqual(pm.steps[1], PlanCode.Line(product: 1, amount: "Pea-size", how: "On dry skin", on: .nights([0])))
        XCTAssertEqual(pm.easeIn, [EaseInPhase(days: 14, extraRest: 1)])
        XCTAssertEqual(read.routines[.am]?.steps[0].on, .weekdays([1, 3, 5]))
        XCTAssertEqual(read.routines[.body]?.name, "Back")
        XCTAssertEqual(read.routines[.body]?.cue, "After shower")
    }

    func testAWebLinkCanCarryTheSameCode() throws {
        let code = try cyclingCode()
        XCTAssertEqual(try PlanCode(link: "https://example.com/c#plan/" + code.payload), code)
        XCTAssertEqual(try PlanCode(link: "  BARRIER://plan/" + code.payload + "\n"), code)
    }

    func testOtherCodesAndLinksAreNotRoutineCodes() {
        for text in ["", "hello", "https://example.com/menu", "barrier://today", "barrier://ritual/pm/2026-11-10", "WIFI:T:WPA;S:Clinic;P:guest;;"] {
            XCTAssertFalse(PlanCode.isLink(text))
            XCTAssertThrowsError(try PlanCode(link: text)) { XCTAssertEqual($0 as? PlanCodeError, .notACode) }
        }
    }

    func testADamagedCodeIsUnreadable() throws {
        let good = try retinoidCode().link
        for text in ["barrier://plan/", "barrier://plan/!!!", String(good.dropLast(11)), String(good.prefix(60)), link("[1,2]"), link("\"v\"")] {
            XCTAssertThrowsError(try PlanCode(link: text), text) { XCTAssertEqual($0 as? PlanCodeError, .unreadable) }
        }
    }

    func testACodeFromANewerVersionSaysSo() {
        XCTAssertThrowsError(try PlanCode(link: link(#"{"v":2,"z":{"anything":true}}"#))) { XCTAssertEqual($0 as? PlanCodeError, .newer) }
    }

    func testEveryBrokenRuleRefusesTheWholeCode() {
        let p = #""p":[{"n":"Tretinoin","k":"retinoid"}]"#
        assertInvalid(#"{\#(p),"pm":{"s":[{"p":0}]}}"#, "no version")
        assertInvalid(#"{"v":0,\#(p),"pm":{"s":[{"p":0}]}}"#, "version 0")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}]},"x":1}"#, "unknown key \"x\"")
        assertInvalid(#"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid","strength":"0.05%"}],"pm":{"s":[{"p":0}]}}"#, "unknown key \"strength\"")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"every":2}]}}"#, "unknown key \"every\"")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"t":"21:30"}}"#, "unknown key \"t\"")
        assertInvalid(#"{"v":1,"p":"Tretinoin","pm":{"s":[{"p":0}]}}"#, "wrong shape")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"w":"20"}]}}"#, "wrong shape")
        assertInvalid(#"{"v":1,"p":[{"n":"BPC","k":"peptide"}],"pm":{"s":[{"p":0}]}}"#, "unknown kind")
        assertInvalid(#"{"v":1,"p":[{"n":"   ","k":"retinoid"}],"pm":{"s":[{"p":0}]}}"#, "no name")
        assertInvalid(#"{"v":1,"p":[{"n":"\#(String(repeating: "a", count: 81))","k":"retinoid"}],"pm":{"s":[{"p":0}]}}"#, "longer than 80")
        assertInvalid(#"{"v":1,"p":[{"n":"Tret\u0007inoin","k":"retinoid"}],"pm":{"s":[{"p":0}]}}"#, "can't be shown")
        assertInvalid(#"{"v":1,"p":[{"n":"Tret\ninoin","k":"retinoid"}],"pm":{"s":[{"p":0}]}}"#, "can't be shown")
        assertInvalid(#"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid","o":"every ‮thgin"}],"pm":{"s":[{"p":0}]}}"#, "can't be shown")
        assertInvalid(#"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid","d":0}],"pm":{"s":[{"p":0}]}}"#, "a course is")
        assertInvalid(#"{"v":1,\#(p)}"#, "no routine")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[]}}"#, "needs 1 to 16 steps")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":1}]}}"#, "no such product")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0},{"p":0}]}}"#, "already in this routine")
        assertInvalid(#"{"v":1,\#(p),"pm":{"l":13,"s":[{"p":0}]}}"#, "a rotation is")
        assertInvalid(#"{"v":1,\#(p),"pm":{"l":2,"s":[{"p":0,"n":[2]}]}}"#, "bad rotation positions")
        assertInvalid(#"{"v":1,\#(p),"pm":{"l":2,"s":[{"p":0,"n":[]}]}}"#, "bad rotation positions")
        assertInvalid(#"{"v":1,\#(p),"pm":{"l":2,"s":[{"p":0,"n":[0,0]}]}}"#, "bad rotation positions")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"d":[7]}]}}"#, "bad weekdays")
        assertInvalid(#"{"v":1,\#(p),"pm":{"l":2,"s":[{"p":0,"n":[0],"d":[1]}]}}"#, "both rotation positions and weekdays")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"w":0}]}}"#, "a wait is")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"w":500}]}}"#, "a wait is")
        assertInvalid(#"{"v":1,\#(p),"am":{"s":[{"p":0}],"e":[[14,1]]}}"#, "only the evening eases in")
        assertInvalid(#"{"v":1,"p":[{"n":"Moisturizer","k":"moisturizer"}],"pm":{"s":[{"p":0}],"e":[[14,1]]}}"#, "easing in needs")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"e":[[10,1]]}}"#, "an ease-in phase is")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"e":[[14,7]]}}"#, "an ease-in phase is")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"e":[[14,1,1]]}}"#, "[days, extra recovery nights]")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"e":[]}}"#, "empty ease-in")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"n":"Evening"}}"#, "only the body routine")
        assertInvalid(#"{"v":1,\#(p),"body":{"s":[{"p":0}]}}"#, "needs a name")
        assertInvalid(#"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid"},{"n":"Spare","k":"serum"}],"pm":{"s":[{"p":0}]}}"#, "isn't used")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}]},"body":{"s":[{"p":0}],"n":"Back"}}"#, "both a face and the body")

        let many = (0..<25).map { #"{"n":"Product \#($0)","k":"serum"}"# }.joined(separator: ",")
        assertInvalid(#"{"v":1,"p":[\#(many)],"pm":{"s":[{"p":0}]}}"#, "needs 1 to 24 products")
        let products = (0..<17).map { #"{"n":"Product \#($0)","k":"serum"}"# }.joined(separator: ",")
        let steps = (0..<17).map { #"{"p":\#($0)}"# }.joined(separator: ",")
        assertInvalid(#"{"v":1,"p":[\#(products)],"pm":{"s":[\#(steps)]}}"#, "needs 1 to 16 steps")

        XCTAssertThrowsError(try PlanCode(link: "barrier://plan/" + String(repeating: "A", count: 2601))) {
            XCTAssertEqual($0 as? PlanCodeError, .invalid("too long"))
        }
    }

    func testACodeThatWouldNotFitInOneQRCodeIsRefused() {
        // 24 products with full-length notes: far more text than one code holds.
        let note = String(repeating: "Apply a thin layer. ", count: 14)
        let items = (0..<24).map { PlanCode.Item(name: "Product \($0)", kind: .serum, note: note) }
        XCTAssertThrowsError(try PlanCode(products: items, routines: [
            .pm: .init(steps: (0..<16).map { .init(product: $0) }), .am: .init(steps: (16..<24).map { .init(product: $0) }),
        ])) { XCTAssertEqual($0 as? PlanCodeError, .invalid("too much text to fit in one code")) }
    }

    func testEquivalentWaysToWriteAScheduleReadTheSame() throws {
        // Every position of a rotation is "every time"; a rotation nobody uses is no rotation; text is trimmed.
        let a = try PlanCode(link: link(#"{"v":1,"p":[{"n":"  Tretinoin ","k":"retinoid","o":"  "}],"pm":{"l":2,"s":[{"p":0,"n":[1,0],"a":" Pea-size "}]}}"#))
        let b = try PlanCode(products: [.init(name: "Tretinoin", kind: .retinoid)], routines: [.pm: .init(steps: [.init(product: 0, amount: "Pea-size")])])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.routines[.pm]?.length, 1)
        XCTAssertNil(a.products[0].note)
    }

    func testARealRoutineFitsAPrintableCode() throws {
        // Version 25 at medium error correction holds 997 bytes: about 5 cm on paper at a comfortable module size.
        XCTAssertLessThan(try retinoidCode().link.utf8.count, 997)
        XCTAssertLessThan(try cyclingCode().link.utf8.count, 400)
    }

    func testACodeCanBeMadeFromARoutine() throws {
        let demo = Presets.demoState(today: today)
        let code = try PlanCode(demo, clinic: "Dr. Petrauskienė", today: today)
        XCTAssertEqual(code.slots, [.am, .pm, .body])
        XCTAssertEqual(try PlanCode(link: code.link), code)

        // Loaded on another phone, it's the same routine in the same words.
        func words(_ s: AppState) -> [String] {
            PlanSnapshot.of(s, day: today).items.map { "\($0.slot.rawValue)|\($0.name)|\($0.schedule)|\($0.amount ?? "")" }
        }
        let other = Presets.blankState(today: today).loading(code, today: today)
        XCTAssertEqual(words(other), words(demo))
        XCTAssertEqual(other.plan.pm.easeIn?.phases, demo.plan.pm.easeIn?.phases)
        XCTAssertEqual(other.plan.pm.easeIn?.start, today)
        XCTAssertEqual(other.plan.body.displayName, "Back")
        XCTAssertEqual(other.plan.body.cue, "After shower")
        XCTAssertEqual(other.plan.ifIrritated, demo.plan.ifIrritated)

        // Only the evening.
        XCTAssertEqual(try PlanCode(demo, slots: [.pm], today: today).slots, [.pm])
    }

    // MARK: Loading

    func testLoadingIntoANewApp() throws {
        let s = Presets.blankState(today: today).loading(try retinoidCode(), today: today)
        XCTAssertEqual(s.products.map(\.name).sorted(), ["Azelaic acid 15%", "Doxycycline 40 mg", "Gentle cleanser", "Moisturizer", "Sunscreen SPF 30+", "Tretinoin 0.025% cream"])
        XCTAssertFalse(s.plan.body.enabled)
        XCTAssertEqual(s.plan.ifIrritated, "Skip tretinoin for 2 nights, moisturizer only, then restart every other night.")

        let tonight = Engine.instance(s, slot: .pm, on: today, today: today)
        XCTAssertEqual(tonight.pos, 0)
        XCTAssertEqual(tonight.label, "Retinoid night")
        XCTAssertEqual(tonight.steps.map(\.product.name), ["Gentle cleanser", "Tretinoin 0.025% cream", "Moisturizer"])
        XCTAssertEqual(tonight.steps[0].step.waitMin, 20)
        XCTAssertTrue(tonight.easing)
        // Weeks 1-2: every 3rd night.
        let week = Engine.timeline(s, slot: .pm, from: today, to: today.adding(5), today: today)
        XCTAssertEqual(week.map(\.hasActives), [true, false, false, true, false, false])
        XCTAssertEqual(s.plan.pm.easeIn, EaseIn(start: today, phases: [EaseInPhase(days: 14, extraRest: 2), EaseInPhase(days: 14, extraRest: 1)]))

        let morning = Engine.instance(s, slot: .am, on: today, today: today)
        XCTAssertEqual(morning.steps.map(\.product.name), ["Doxycycline 40 mg", "Gentle cleanser", "Azelaic acid 15%", "Moisturizer", "Sunscreen SPF 30+"])

        let doxy = try XCTUnwrap(s.products.first { $0.kind == .oral })
        XCTAssertEqual(doxy.from, today)
        XCTAssertEqual(doxy.until, today.adding(83))
        XCTAssertEqual(doxy.note, "With food and a full glass of water.")
        XCTAssertFalse(Engine.instance(s, slot: .am, on: today.adding(84), today: today).steps.contains { $0.product.kind == .oral })
        XCTAssertNil(s.products.first { $0.kind == .cleanser }?.from)
        XCTAssertEqual(s.products.first { $0.kind == .retinoid }?.from, today)
    }

    func testOnlyTheRoutinesInTheCodeAreReplaced() throws {
        let before = Presets.demoState(today: today)
        let oldLotion = try XCTUnwrap(before.plan.body.steps.first?.productId)
        let s = before.loading(try backCode(), today: today)

        XCTAssertEqual(s.plan.am, before.plan.am)
        XCTAssertEqual(s.plan.pm, before.plan.pm)
        XCTAssertEqual(s.plan.ifIrritated, before.plan.ifIrritated)
        XCTAssertEqual(s.plan.followUp, before.plan.followUp)
        XCTAssertEqual(s.plan.body.steps.count, 1)
        XCTAssertEqual(s.plan.body.steps[0].on, .weekdays([1, 3, 5]))
        XCTAssertEqual(s.plan.body.time, before.plan.body.time)
        XCTAssertNil(s.product(oldLotion), "the old lotion is gone with its step")
        XCTAssertEqual(s.product(s.plan.body.steps[0].productId)?.name, "Benzoyl peroxide wash 5%")
        XCTAssertEqual(Set(s.products.map(\.id)).subtracting([s.plan.body.steps[0].productId]), Set(before.products.map(\.id)).subtracting([oldLotion]))

        // Nothing else moves.
        XCTAssertEqual(s.log, before.log)
        XCTAssertEqual(s.photos, before.photos)
        XCTAssertEqual(s.checkins, before.checkins)
        XCTAssertEqual(s.pauses, before.pauses)
        XCTAssertEqual(s.procedures, before.procedures)
        XCTAssertEqual(s.scores, before.scores)
        XCTAssertEqual(s.questions, before.questions)
        XCTAssertEqual(s.settings, before.settings)
        XCTAssertEqual(s.history, before.history)
    }

    func testTheSameProductKeepsItsFirstDayOfUse() throws {
        let start = today.adding(-60)
        var s = onboarded(.retinoid, since: start)
        let tret = try XCTUnwrap(s.products.firstIndex { $0.kind == .retinoid })
        s.products[tret].name = "Tretinoin 0.025% cream"
        s.plan.pm.easeIn = nil
        s.recordPlan(today: start)
        let id = s.products[tret].id

        // The follow-up visit: a stronger cream, every other night to begin with.
        let code = try PlanCode(
            products: [.init(name: "Gentle cleanser", kind: .cleanser), .init(name: "Tretinoin 0.05% cream", kind: .retinoid), .init(name: "Moisturizer", kind: .moisturizer)],
            routines: [.pm: .init(length: 2, steps: [.init(product: 0), .init(product: 1, amount: "Pea-size for the whole face", on: .nights([0])), .init(product: 2)])])
        var after = s.loading(code, today: today)
        after.recordPlan(today: today)

        let now = try XCTUnwrap(after.product(id), "the same product, not a new one")
        XCTAssertEqual(now.name, "Tretinoin 0.05% cream")
        XCTAssertEqual(now.from, start)
        XCTAssertEqual(after.products.filter { $0.kind == .retinoid }.count, 1)
        XCTAssertEqual(after.plan.am, s.plan.am)
        XCTAssertEqual(PlanHistory.changes(after).last?.lines, ["Tretinoin: 0.025% → 0.05%", "Tretinoin 0.05% cream: every night → every other night"])
    }

    func testAFaceProductIsNeverReusedForTheBody() throws {
        var s = onboarded(.simple, since: today.adding(-10))
        let face = Product(name: "Clindamycin lotion", kind: .treatment, from: today.adding(-10))
        s.products.append(face)
        s.plan.am.steps.append(Step(productId: face.id))
        let code = try PlanCode(products: [.init(name: "Clindamycin lotion", kind: .treatment)], routines: [.body: .init(steps: [.init(product: 0)], name: "Chest")])
        let after = s.loading(code, today: today)

        let bodyProduct = try XCTUnwrap(after.plan.body.steps.first?.productId)
        XCTAssertNotEqual(bodyProduct, face.id)
        XCTAssertEqual(after.product(bodyProduct)?.from, today)
        XCTAssertEqual(after.product(face.id)?.from, today.adding(-10))
        XCTAssertTrue(after.plan.am.steps.contains { $0.productId == face.id })
        XCTAssertEqual(after.plan.body.displayName, "Chest")
        XCTAssertTrue(after.plan.body.enabled)
    }

    func testANightAlreadyLoggedStartsTheNewRoutineTomorrow() throws {
        for skipped in [false, true] {
            var s = onboarded(.simple, since: today.adding(-5))
            if skipped { s.markSkipped(.pm, on: today, today: today) } else { s.markDone(.pm, on: today, today: today) }
            XCTAssertEqual(s.loadDay(.pm, today: today), today.adding(1))
            XCTAssertEqual(s.loadDay(.am, today: today), today)

            let code = try PlanCode(
                products: [.init(name: "Cleanser", kind: .cleanser), .init(name: "Glycolic acid 7%", kind: .exfoliant), .init(name: "Retinol serum", kind: .retinoid),
                           .init(name: "Moisturizer", kind: .moisturizer), .init(name: "Sunscreen", kind: .spf)],
                routines: [.pm: .init(length: 4, steps: [.init(product: 0), .init(product: 1, on: .nights([0])), .init(product: 2, on: .nights([1])), .init(product: 3)]),
                           .am: .init(steps: [.init(product: 0), .init(product: 3), .init(product: 4)])])
            let after = s.loading(code, today: today)

            // Tonight stays as it was logged; night 1 of the new rotation is tomorrow.
            let tonight = Engine.instance(after, slot: .pm, on: today, today: today)
            XCTAssertEqual(tonight.status, skipped ? .skipped : .done)
            let next = Engine.timeline(after, slot: .pm, from: today.adding(1), to: today.adding(4), today: today)
            XCTAssertEqual(next.map(\.pos), [0, 1, 2, 3])
            XCTAssertEqual(next.map(\.label), ["Exfoliation night", "Retinoid night", "Recovery night", "Recovery night"])
            XCTAssertEqual(after.products.first { $0.kind == .exfoliant }?.from, today.adding(1))
            // The morning wasn't logged: it starts today.
            XCTAssertEqual(Engine.instance(after, slot: .am, on: today, today: today).steps.count, 3)
            XCTAssertEqual(Engine.instance(after, slot: .am, on: today, today: today).status, .pending)
            XCTAssertEqual(Engine.needsReconcile(after, today: today.adding(1)), [])
        }
    }

    func testARecoveryNightChosenTonightStaysARecoveryNight() throws {
        var s = onboarded(.retinoid, since: today.adding(-40))
        s.setRecovery(today, .pm, on: true)
        let after = s.loading(try cyclingCode(), today: today)
        let tonight = Engine.instance(after, slot: .pm, on: today, today: today)
        XCTAssertEqual(tonight.rest, .inserted)
        XCTAssertFalse(tonight.steps.contains { $0.active })
        // The rotation waits: night 1 is tomorrow.
        XCTAssertEqual(Engine.instance(after, slot: .pm, on: today.adding(1), today: today).label, "Exfoliation night")
    }

    func testLoadingTheSameCodeTwiceChangesNothing() throws {
        for (code, state) in [(try retinoidCode(), Presets.demoState(today: today)), (try backCode(), Presets.demoState(today: today)),
                              (try cyclingCode(), onboarded(.cycling, since: today.adding(-9)))] {
            let once = state.loading(code, today: today)
            XCTAssertEqual(once.loading(code, today: today), once)
        }
    }

    func testTheOldRoutineLeavesNoQuestionBehind() throws {
        // Last night's retinoid night was never logged. The new plan starts today: nothing to ask about the old one.
        let s = onboarded(.cycling, since: today.adding(-6))
        XCTAssertFalse(Engine.needsReconcile(s, today: today).isEmpty)
        let after = s.loading(try retinoidCode(), today: today)
        XCTAssertEqual(Engine.needsReconcile(after, today: today), [])
    }

    // MARK: In words

    func testTheSummaryReadsLikeTheClinicsSheet() throws {
        let sum = try retinoidCode().summary(for: Presets.blankState(today: today), today: today)
        XCTAssertEqual(sum.clinic, "Dr. Petrauskienė")
        XCTAssertEqual(sum.sections.map(\.title), ["Morning", "Evening"])
        XCTAssertEqual(sum.sections.map(\.replaces), [false, false])
        XCTAssertEqual(sum.sections.map(\.starts), [today, today])

        let am = sum.sections[0]
        XCTAssertEqual(am.rows.map(\.name), ["Doxycycline 40 mg", "Gentle cleanser", "Azelaic acid 15%", "Moisturizer", "Sunscreen SPF 30+"])
        XCTAssertEqual(am.rows[0].lines, ["Every morning", "For 12 weeks, until Feb 1"])
        XCTAssertEqual(am.rows[0].note, "With food and a full glass of water.")
        XCTAssertEqual(am.rows[2].lines, ["Every morning · Thin layer"])
        XCTAssertEqual(am.easeIn, [])
        XCTAssertNil(am.rotation)

        let pm = sum.sections[1]
        XCTAssertEqual(pm.rows[0].lines, ["Every night", "Then wait 20 minutes"])
        XCTAssertEqual(pm.rows[1].lines, ["Every night · Pea-size", "On completely dry skin"])
        XCTAssertEqual(pm.rows[1].note, "Avoid the corners of the nose and mouth.")
        XCTAssertEqual(pm.easeIn, ["Weeks 1–2: actives every 3rd night", "Weeks 3–4: actives every other night", "From week 5: the full routine"])
        XCTAssertEqual(sum.ifIrritated, "Skip tretinoin for 2 nights, moisturizer only, then restart every other night.")
    }

    func testTheSummarySaysWhatGetsReplacedAndWhenItStarts() throws {
        var s = Presets.demoState(today: today)
        s.markDone(.pm, on: today, today: today)
        let cycling = try cyclingCode().summary(for: s, today: today)
        XCTAssertEqual(cycling.sections.map(\.title), ["Evening"])
        XCTAssertEqual(cycling.sections[0].replaces, true)
        XCTAssertEqual(cycling.sections[0].starts, today.adding(1))
        XCTAssertEqual(cycling.sections[0].rotation, "Repeats every 4 nights")
        XCTAssertEqual(cycling.sections[0].rows.map { $0.lines[0] }, ["Every night", "Every 4th night", "Every 4th night", "Every night"])

        let back = try backCode().summary(for: Presets.blankState(today: today), today: today)
        XCTAssertEqual(back.sections[0].title, "Back")
        XCTAssertEqual(back.sections[0].rows[0].lines, ["Mon, Wed, Fri"])
        XCTAssertEqual(back.sections[0].replaces, false)
    }

    func testTheScreenshotCodeLoadsIntoTheDemo() throws {
        let code = try XCTUnwrap(Presets.demoCode)
        XCTAssertEqual(code.slots, [.am, .pm, .body])
        XCTAssertEqual(try PlanCode(link: code.link), code)
        let demo = Presets.demoState(today: today)
        let after = demo.loading(code, today: today)
        XCTAssertEqual(after.plan.am.steps.compactMap { after.product($0.productId)?.name },
                       ["Doxycycline 40 mg", "Gentle cleanser", "Azelaic acid 15%", "Moisturizer", "Sunscreen SPF 30+"])
        XCTAssertEqual(after.plan.pm.steps.compactMap { after.product($0.productId)?.name }, ["Gentle cleanser", "Tretinoin 0.05% cream", "Moisturizer"])
        XCTAssertEqual(after.plan.body.displayName, "Back")
        XCTAssertEqual(after.history, demo.history)
        XCTAssertEqual(after.log, demo.log)
    }

    func testCourseAndEaseInWords() {
        XCTAssertEqual(PlanCode.courseText(1), "1 day")
        XCTAssertEqual(PlanCode.courseText(7), "1 week")
        XCTAssertEqual(PlanCode.courseText(10), "10 days")
        XCTAssertEqual(PlanCode.courseText(84), "12 weeks")
        XCTAssertEqual(PlanCode.easeInLines([], length: 1), [])
        XCTAssertEqual(PlanCode.easeInLines([EaseInPhase(days: 7, extraRest: 3), EaseInPhase(days: 21, extraRest: 0)], length: 1),
                       ["Week 1: actives every 4th night", "Weeks 2–4: actives every night", "From week 5: the full routine"])
        XCTAssertEqual(PlanCode.easeInLines([EaseInPhase(days: 14, extraRest: 1), EaseInPhase(days: 14, extraRest: 2)], length: 4),
                       ["Weeks 1–2: 1 extra recovery night in each cycle", "Weeks 3–4: 2 extra recovery nights in each cycle", "From week 5: the full routine"])
    }
}
