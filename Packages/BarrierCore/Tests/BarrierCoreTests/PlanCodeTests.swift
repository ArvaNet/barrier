import XCTest
@testable import BarrierCore

/// A routine handed over by a clinic as a QR code: the text form, its rules, and what loading it does.
final class PlanCodeTests: XCTestCase {
    let today = Day(2026, 11, 10)
    let slowly = Presets.buildUpStages

    /// Tretinoin starting slowly with a wait after cleansing, azelaic acid and a 12-week course in the morning.
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
                .pm: .init(steps: [.init(product: 0, waitMin: 20),
                                   .init(product: 1, amount: "Pea-size", how: "On completely dry skin", buildUp: slowly),
                                   .init(product: 2)]),
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

    /// Two body routines: a wash and a moisturizer after the shower, adapalene on the back
    /// before bed, starting slowly. The moisturizer is in both.
    func twoBodyCode() throws -> PlanCode {
        try PlanCode(
            products: [
                .init(name: "Benzoyl peroxide wash 5%", kind: .treatment),
                .init(name: "Body moisturizer", kind: .moisturizer),
                .init(name: "Adapalene 0.1% gel", kind: .retinoid),
            ],
            routines: [
                .body: .init(steps: [.init(product: 0), .init(product: 1)], name: "Body", cue: "After shower"),
                .body2: .init(steps: [.init(product: 2, amount: "Thin layer", buildUp: [BuildStage(every: 2, days: 14)]), .init(product: 1)],
                              name: "Back", cue: "Before bed"),
            ])
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

    func step(_ s: AppState, _ slot: Slot = .pm, kind: ProductKind) -> Step? {
        s.plan[slot].steps.first { s.product($0.productId)?.kind == kind }
    }

    /// Whether a step is on each of the next `n` days, from `from`.
    func due(_ s: AppState, _ slot: Slot = .pm, step id: String, from: Day, _ n: Int, today: Day) -> [Bool] {
        Engine.timeline(s, slot: slot, from: from, to: from.adding(n - 1), today: today).map { $0.steps.contains { $0.step.id == id } }
    }

    // MARK: The text form

    func testACodeSurvivesTheTripThroughItsLink() throws {
        for code in [try retinoidCode(), try cyclingCode(), try backCode(), try twoBodyCode()] {
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

        // Starting slowly, as the app writes it.
        let slow = try PlanCode(products: [.init(name: "Tretinoin", kind: .retinoid)], routines: [.pm: .init(steps: [.init(product: 0, buildUp: slowly)])])
        XCTAssertEqual(slow.payload, "eyJwIjpbeyJrIjoicmV0aW5vaWQiLCJuIjoiVHJldGlub2luIn1dLCJwbSI6eyJzIjpbeyJiIjpbWzMsMTRdLFsyLDE0XV0sInAiOjB9XX0sInYiOjF9")
        XCTAssertEqual(try PlanCode(link: link(#"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid"}],"pm":{"s":[{"p":0,"b":[[3,14],[2,14]]}]}}"#)), slow)

        // Every key, written by hand the way the clinic page writes it.
        let full = """
        {"v":1,"c":"Dr. Petrauskienė","i":"Stop for two nights.","p":[{"n":"Cleanser","k":"cleanser"},{"n":"Tretinoin 0.025% cream","k":"retinoid","o":"Avoid the eyes."},\
        {"n":"Antibiotic","k":"oral","d":84},{"n":"Lotion","k":"treatment"}],\
        "pm":{"l":2,"s":[{"p":0,"w":20},{"p":1,"a":"Pea-size","h":"On dry skin","n":[0],"b":[[4,14],[3,7]]}]},\
        "am":{"s":[{"p":2,"d":[1,3,5]},{"p":0}]},"body":{"s":[{"p":3}],"n":"Back","q":"After shower"},\
        "body2":{"s":[{"p":3}],"n":"Back","q":"Before bed"}}
        """
        let read = try PlanCode(link: link(full))
        XCTAssertEqual(read.clinic, "Dr. Petrauskienė")
        XCTAssertEqual(read.ifIrritated, "Stop for two nights.")
        XCTAssertEqual(read.products.map(\.kind), [.cleanser, .retinoid, .oral, .treatment])
        XCTAssertEqual(read.products[1].note, "Avoid the eyes.")
        XCTAssertEqual(read.products[2].courseDays, 84)
        XCTAssertEqual(read.slots, [.pm, .am, .body, .body2])
        let pm = try XCTUnwrap(read.routines[.pm])
        XCTAssertEqual(pm.length, 2)
        XCTAssertEqual(pm.steps[0].waitMin, 20)
        XCTAssertEqual(pm.steps[1], PlanCode.Line(product: 1, amount: "Pea-size", how: "On dry skin", on: .nights([0]),
                                                  buildUp: [BuildStage(every: 4, days: 14), BuildStage(every: 3, days: 7)]))
        XCTAssertEqual(read.routines[.am]?.steps[0].on, .weekdays([1, 3, 5]))
        XCTAssertEqual(read.routines[.body]?.name, "Back")
        XCTAssertEqual(read.routines[.body]?.cue, "After shower")
        XCTAssertEqual(read.routines[.body2]?.name, "Back")
        XCTAssertEqual(read.routines[.body2]?.cue, "Before bed")
        XCTAssertEqual(read.routines[.body2]?.steps, [PlanCode.Line(product: 3)])
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
        // The old routine-wide ease-in is gone from the format.
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"e":[[14,1]]}}"#, "unknown key \"e\"")
        assertInvalid(#"{"v":1,"p":"Tretinoin","pm":{"s":[{"p":0}]}}"#, "wrong shape")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"w":"20"}]}}"#, "wrong shape")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[3,14]}]}}"#, "wrong shape")
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

        // Starting slowly: exactly what the step editor lets a person set.
        assertInvalid(#"{"v":1,"p":[{"n":"Moisturizer","k":"moisturizer"}],"pm":{"s":[{"p":0,"b":[[3,14]]}]}}"#, "only a retinoid, exfoliant or treatment starts slowly")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"d":[1,4],"b":[[3,14]]}]}}"#, "starting slowly needs a goal")
        assertInvalid(#"{"v":1,\#(p),"pm":{"l":3,"s":[{"p":0,"n":[0,1],"b":[[4,14]]}]}}"#, "starting slowly needs a goal")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[4,7],[4,7],[3,7],[3,7],[2,7]]}]}}"#, "a build-up has 1 to 4 stages")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[1,14]]}]}}"#, "each stage is every 2nd, 3rd or 4th time")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[5,14]]}]}}"#, "each stage is every 2nd, 3rd or 4th time")
        assertInvalid(#"{"v":1,\#(p),"pm":{"l":2,"s":[{"p":0,"n":[0],"b":[[2,14]]}]}}"#, "less often than the goal")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[3,10]]}]}}"#, "each stage is 1 to 8 whole weeks")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[3,63]]}]}}"#, "each stage is 1 to 8 whole weeks")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[3,0]]}]}}"#, "each stage is 1 to 8 whole weeks")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[2,14],[3,14]]}]}}"#, "from the slowest to the fastest")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[[3]]}]}}"#, "a stage is [every, days]")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0,"b":[]}]}}"#, "an empty build-up")
        // Every 5th night of glycolic acid leaves no room for every 3rd night of tretinoin: the rotation would be 15 nights.
        assertInvalid(#"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid"},{"n":"Glycolic acid","k":"exfoliant"}],"pm":{"l":5,"s":[{"p":1,"n":[0]},{"p":0,"b":[[3,14]]}]}}"#,
                      "a build-up doesn't fit the rotation")

        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}],"n":"Evening"}}"#, "only a body routine")
        assertInvalid(#"{"v":1,\#(p),"body":{"s":[{"p":0}]}}"#, "needs a name")
        assertInvalid(#"{"v":1,\#(p),"body2":{"s":[{"p":0}]}}"#, "the body2 routine needs a name")
        assertInvalid(#"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid"},{"n":"Spare","k":"serum"}],"pm":{"s":[{"p":0}]}}"#, "isn't used")
        assertInvalid(#"{"v":1,\#(p),"pm":{"s":[{"p":0}]},"body":{"s":[{"p":0}],"n":"Back"}}"#, "both a face and a body")
        assertInvalid(#"{"v":1,\#(p),"am":{"s":[{"p":0}]},"body2":{"s":[{"p":0}],"n":"Back"}}"#, "both a face and a body")

        let many = (0..<25).map { #"{"n":"Product \#($0)","k":"serum"}"# }.joined(separator: ",")
        assertInvalid(#"{"v":1,"p":[\#(many)],"pm":{"s":[{"p":0}]}}"#, "needs 1 to 24 products")
        let products = (0..<17).map { #"{"n":"Product \#($0)","k":"serum"}"# }.joined(separator: ",")
        let steps = (0..<17).map { #"{"p":\#($0)}"# }.joined(separator: ",")
        assertInvalid(#"{"v":1,"p":[\#(products)],"pm":{"s":[\#(steps)]}}"#, "needs 1 to 16 steps")

        XCTAssertThrowsError(try PlanCode(link: "barrier://plan/" + String(repeating: "A", count: 2601))) {
            XCTAssertEqual($0 as? PlanCodeError, .invalid("too long"))
        }
    }

    func testTheEditorsWholeRangeOfBuildUpsIsAllowed() throws {
        let p = #""p":[{"n":"Tretinoin","k":"retinoid"},{"n":"Glycolic acid","k":"exfoliant"},{"n":"Azelaic acid","k":"treatment"}]"#
        for json in [
            // Four stages, every 4th down to every other, 1 and 8 weeks.
            #"{"v":1,"p":[{"n":"Tretinoin","k":"retinoid"}],"pm":{"s":[{"p":0,"b":[[4,7],[4,56],[3,14],[2,14]]}]}}"#,
            // Every other night as the goal, in a rotation; an exfoliant in the morning; a treatment on the back.
            #"{"v":1,\#(p),"pm":{"l":2,"s":[{"p":0,"n":[1],"b":[[4,14]]}]},"am":{"s":[{"p":1,"b":[[3,7]]}]},"body":{"n":"Back","s":[{"p":2,"b":[[3,14],[3,14]]}]}}"#,
        ] {
            let code = try PlanCode(link: link(json))
            XCTAssertEqual(try PlanCode(link: code.link), code)
            let s = Presets.blankState(today: today).loading(code, today: today)
            for slot in code.slots {
                for (i, line) in try XCTUnwrap(code.routines[slot]).steps.enumerated() where !line.buildUp.isEmpty {
                    XCTAssertEqual(s.plan[slot].steps[i].buildUp?.stages, line.buildUp)
                }
            }
        }
        // A product can be in both body routines.
        let both = try twoBodyCode()
        XCTAssertEqual(both.slots, [.body, .body2])
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
        let a = try PlanCode(link: link(#"{"v":1,"p":[{"n":"  Tretinoin ","k":"retinoid","o":"  "}],"pm":{"l":2,"s":[{"p":0,"n":[1,0],"a":" Pea-size ","b":[[3,14]]}]}}"#))
        let b = try PlanCode(products: [.init(name: "Tretinoin", kind: .retinoid)],
                             routines: [.pm: .init(steps: [.init(product: 0, amount: "Pea-size", buildUp: [BuildStage(every: 3, days: 14)])])])
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
        XCTAssertEqual(code.slots, [.pm, .am, .body])
        XCTAssertEqual(try PlanCode(link: code.link), code)
        // The build-up is written at its goal, with its stages.
        XCTAssertEqual(code.routines[.pm]?.length, 1)
        XCTAssertEqual(code.routines[.pm]?.steps.first { !$0.buildUp.isEmpty }?.on, .all)

        // Loaded on another phone, it's the same routine in the same words.
        func words(_ s: AppState) -> [String] {
            PlanSnapshot.of(s, day: today).items.map { "\($0.slot.rawValue)|\($0.name)|\($0.schedule)|\($0.amount ?? "")|\($0.goal ?? "")" }
        }
        let other = Presets.blankState(today: today).loading(code, today: today)
        XCTAssertEqual(words(other), words(demo))
        let tret = try XCTUnwrap(step(other, kind: .retinoid)?.buildUp)
        XCTAssertEqual(tret, BuildUp(start: today, stages: slowly, goal: 1))
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
        XCTAssertFalse(s.plan.body2.enabled)
        XCTAssertEqual(s.plan.ifIrritated, "Skip tretinoin for 2 nights, moisturizer only, then restart every other night.")

        let tonight = Engine.instance(s, slot: .pm, on: today, today: today)
        XCTAssertEqual(tonight.pos, 0)
        XCTAssertEqual(tonight.label, "Retinoid night")
        XCTAssertEqual(tonight.steps.map(\.product.name), ["Gentle cleanser", "Tretinoin 0.025% cream", "Moisturizer"])
        XCTAssertEqual(tonight.steps[0].step.waitMin, 20)
        XCTAssertNil(s.plan.pm.easeIn)

        // Starting slowly from day 1: due tonight, then every 3rd night, no moves yet.
        let tret = try XCTUnwrap(step(s, kind: .retinoid))
        XCTAssertEqual(tret.buildUp, BuildUp(start: today, stages: slowly, goal: 1))
        XCTAssertEqual(due(s, step: tret.id, from: today, 6, today: today), [true, false, false, true, false, false])
        // Nothing moves up by itself: two months on, still every 3rd night, and Tendwell asks.
        let later = today.adding(60)
        XCTAssertEqual(due(s, step: tret.id, from: later, 3, today: today).filter { $0 }.count, 1)
        XCTAssertEqual(BuildUps.asks(s, today: today.adding(13)), [])
        XCTAssertEqual(BuildUps.asks(s, today: today.adding(14)).map(\.from), [3])

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

    func testABuildUpForAProductInUseIsSpacedFromTheLastTime() throws {
        // Tretinoin every night for weeks, last on last night. The clinic now starts a stronger one slowly.
        for loggedTonight in [false, true] {
            var s = onboarded(.retinoid, since: today.adding(-30))
            let tretinoin = try XCTUnwrap(s.products.firstIndex { $0.kind == .retinoid })
            s.products[tretinoin].name = "Tretinoin 0.025% cream"
            let id = try XCTUnwrap(step(s, kind: .retinoid)).id
            s.endBuildUp(.pm, stepID: id, today: today.adding(-30))
            for d in 1...5 { s.markDone(.pm, on: today.adding(-d), today: today.adding(-d)) }
            if loggedTonight { s.markDone(.pm, on: today, today: today) }
            let code = try PlanCode(
                products: [.init(name: "Gentle cleanser", kind: .cleanser), .init(name: "Tretinoin 0.05% cream", kind: .retinoid), .init(name: "Moisturizer", kind: .moisturizer)],
                routines: [.pm: .init(steps: [.init(product: 0), .init(product: 1, buildUp: slowly), .init(product: 2)])])
            let after = s.loading(code, today: today)

            // The same product and step, starting on day 1 with no moves.
            let day1 = loggedTonight ? today.adding(1) : today
            let tret = try XCTUnwrap(step(after, kind: .retinoid))
            XCTAssertEqual(tret.id, id)
            XCTAssertEqual(tret.buildUp, BuildUp(start: day1, stages: slowly, goal: 1))
            // Every 3rd night counted from the last time it went on (waitFor): never two nights running.
            XCTAssertEqual(due(after, step: id, from: day1, 6, today: today), [false, false, true, false, false, true])
            XCTAssertEqual(Engine.instance(after, slot: .pm, on: day1, today: today).pos, 0)
            XCTAssertEqual(after.loading(code, today: today), after)
        }
    }

    func testOnlyTheRoutinesInTheCodeAreReplaced() throws {
        let before = Presets.demoState(today: today)
        let oldLotion = try XCTUnwrap(before.plan.body.steps.first?.productId)
        let s = before.loading(try backCode(), today: today)

        XCTAssertEqual(s.plan.am, before.plan.am)
        XCTAssertEqual(s.plan.pm, before.plan.pm)
        XCTAssertEqual(s.plan.body2, before.plan.body2)
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

    func testTwoBodyRoutinesLoadTogether() throws {
        let s = Presets.blankState(today: today).loading(try twoBodyCode(), today: today)
        XCTAssertTrue(s.plan.body.enabled)
        XCTAssertTrue(s.plan.body2.enabled)
        XCTAssertEqual(s.plan.shortName(.body), "After shower")
        XCTAssertEqual(s.plan.shortName(.body2), "Before bed")
        XCTAssertEqual(s.plan.body2.displayName, "Back")
        // The moisturizer is one product in both routines.
        let lotion = try XCTUnwrap(step(s, .body, kind: .moisturizer)?.productId)
        XCTAssertEqual(step(s, .body2, kind: .moisturizer)?.productId, lotion)
        XCTAssertEqual(s.products.count, 3)
        // Adapalene starts slowly on the back: every other day from day 1, building up to every day.
        let ada = try XCTUnwrap(step(s, .body2, kind: .retinoid))
        XCTAssertEqual(ada.buildUp, BuildUp(start: today, stages: [BuildStage(every: 2, days: 14)], goal: 1))
        XCTAssertEqual(due(s, .body2, step: ada.id, from: today, 4, today: today), [true, false, true, false])

        // A code with only the second body routine leaves the first one alone.
        let demo = Presets.demoState(today: today)
        let only = try PlanCode(products: [.init(name: "Adapalene 0.1% gel", kind: .retinoid)],
                                routines: [.body2: .init(steps: [.init(product: 0, buildUp: slowly)], name: "Back", cue: "Before bed")])
        let after = demo.loading(only, today: today)
        XCTAssertEqual(after.plan.body, demo.plan.body)
        XCTAssertEqual(after.plan.pm, demo.plan.pm)
        XCTAssertTrue(after.plan.body2.enabled)
        XCTAssertEqual(after.loading(only, today: today), after)
    }

    func testTheSameProductKeepsItsFirstDayOfUse() throws {
        let start = today.adding(-60)
        var s = onboarded(.retinoid, since: start)
        let tret = try XCTUnwrap(s.products.firstIndex { $0.kind == .retinoid })
        s.products[tret].name = "Tretinoin 0.025% cream"
        // Built up to every night long ago.
        s.endBuildUp(.pm, stepID: try XCTUnwrap(step(s, kind: .retinoid)).id, today: start)
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
        for slot in Slot.bodies {
            let code = try PlanCode(products: [.init(name: "Clindamycin lotion", kind: .treatment)], routines: [slot: .init(steps: [.init(product: 0)], name: "Chest")])
            let after = s.loading(code, today: today)

            let bodyProduct = try XCTUnwrap(after.plan[slot].steps.first?.productId)
            XCTAssertNotEqual(bodyProduct, face.id)
            XCTAssertEqual(after.product(bodyProduct)?.from, today)
            XCTAssertEqual(after.product(face.id)?.from, today.adding(-10))
            XCTAssertTrue(after.plan.am.steps.contains { $0.productId == face.id })
            XCTAssertEqual(after.plan[slot].displayName, "Chest")
            XCTAssertTrue(after.plan[slot].enabled)
        }
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

    func testABuildUpAfterANightAlreadyLoggedStartsTomorrow() throws {
        // A new product, tonight already done: day 1 is tomorrow, and the build-up starts then.
        var s = onboarded(.simple, since: today.adding(-5))
        s.markDone(.pm, on: today, today: today)
        let after = s.loading(try retinoidCode(), today: today)
        let tret = try XCTUnwrap(step(after, kind: .retinoid))
        XCTAssertEqual(tret.buildUp?.start, today.adding(1))
        XCTAssertEqual(tret.buildUp?.moves, [])
        XCTAssertEqual(Engine.instance(after, slot: .pm, on: today, today: today).status, .done)
        let next = Engine.timeline(after, slot: .pm, from: today.adding(1), to: today.adding(4), today: today)
        XCTAssertEqual(next.first?.pos, 0)
        XCTAssertEqual(next.map { $0.steps.contains { $0.step.id == tret.id } }, [true, false, false, true])
        XCTAssertEqual(after.products.first { $0.kind == .retinoid }?.from, today.adding(1))
    }

    func testARecoveryNightChosenTonightStaysARecoveryNight() throws {
        for (code, night1) in [(try cyclingCode(), "Exfoliation night"), (try retinoidCode(), "Retinoid night")] {
            var s = onboarded(.retinoid, since: today.adding(-40))
            s.setRecovery(today, .pm, on: true)
            let after = s.loading(code, today: today)
            let tonight = Engine.instance(after, slot: .pm, on: today, today: today)
            XCTAssertEqual(tonight.rest, .inserted)
            XCTAssertFalse(tonight.steps.contains { $0.active })
            // The rotation waits: night 1 is tomorrow.
            let tomorrow = Engine.instance(after, slot: .pm, on: today.adding(1), today: today)
            XCTAssertEqual(tomorrow.pos, 0)
            XCTAssertEqual(tomorrow.label, night1)
        }
    }

    func testLoadingTheSameCodeTwiceChangesNothing() throws {
        for (code, state) in [(try retinoidCode(), Presets.demoState(today: today)), (try backCode(), Presets.demoState(today: today)),
                              (try cyclingCode(), onboarded(.cycling, since: today.adding(-9))), (try twoBodyCode(), Presets.demoState(today: today)),
                              (try retinoidCode(), Presets.blankState(today: today))] {
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
        XCTAssertEqual(sum.sections.map(\.title), ["Evening", "Morning"])
        XCTAssertEqual(sum.sections.map(\.replaces), [false, false])
        XCTAssertEqual(sum.sections.map(\.starts), [today, today])

        let pm = sum.sections[0]
        XCTAssertNil(pm.rotation, "the build-up's rotation isn't the sheet's")
        XCTAssertEqual(pm.rows[0].lines, ["Every night", "Then wait 20 minutes"])
        // The build-up sits with its product, in the routine's and the editor's words.
        XCTAssertEqual(pm.rows[1].lines, ["Every 3rd night, building up to every night · Pea-size",
                                          "Every 3rd night for 2 weeks, then every other night for 2 weeks",
                                          "Tendwell asks how your skin is before each move up",
                                          "On completely dry skin"])
        XCTAssertEqual(pm.rows[1].note, "Avoid the corners of the nose and mouth.")
        XCTAssertEqual(pm.rows[2].lines, ["Every night"])

        let am = sum.sections[1]
        XCTAssertEqual(am.rows.map(\.name), ["Doxycycline 40 mg", "Gentle cleanser", "Azelaic acid 15%", "Moisturizer", "Sunscreen SPF 30+"])
        XCTAssertEqual(am.rows[0].lines, ["Every morning", "For 12 weeks, until Feb 1"])
        XCTAssertEqual(am.rows[0].note, "With food and a full glass of water.")
        XCTAssertEqual(am.rows[2].lines, ["Every morning · Thin layer"])
        XCTAssertNil(am.rotation)
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

        // Two body routines go by their moments, as on the Routine tab.
        let two = try twoBodyCode().summary(for: Presets.blankState(today: today), today: today)
        XCTAssertEqual(two.sections.map(\.title), ["After shower", "Before bed"])
        XCTAssertEqual(two.sections[1].rows[0].lines, ["Every other day, building up to every day · Thin layer",
                                                       "Every other day for 2 weeks",
                                                       "Tendwell asks how your skin is before each move up"])
    }

    func testTheScreenshotCodeLoadsIntoTheDemo() throws {
        let code = try XCTUnwrap(Presets.demoCode)
        XCTAssertEqual(code.slots, [.pm, .am, .body])
        XCTAssertEqual(try PlanCode(link: code.link), code)
        let demo = Presets.demoState(today: today)
        let after = demo.loading(code, today: today)
        XCTAssertEqual(after.plan.am.steps.compactMap { after.product($0.productId)?.name },
                       ["Doxycycline 40 mg", "Gentle cleanser", "Azelaic acid 15%", "Moisturizer", "Sunscreen SPF 30+"])
        XCTAssertEqual(after.plan.pm.steps.compactMap { after.product($0.productId)?.name }, ["Gentle cleanser", "Tretinoin 0.05% cream", "Moisturizer"])
        XCTAssertEqual(step(after, kind: .retinoid)?.buildUp, BuildUp(start: today, stages: slowly, goal: 1))
        XCTAssertEqual(after.plan.body.displayName, "Back")
        XCTAssertEqual(after.history, demo.history)
        XCTAssertEqual(after.log, demo.log)
    }

    func testCourseAndBuildUpWords() {
        XCTAssertEqual(PlanCode.courseText(1), "1 day")
        XCTAssertEqual(PlanCode.courseText(7), "1 week")
        XCTAssertEqual(PlanCode.courseText(10), "10 days")
        XCTAssertEqual(PlanCode.courseText(84), "12 weeks")
        XCTAssertEqual(PlanCode.buildUpLines([], word: "night"), [])
        XCTAssertEqual(PlanCode.buildUpLines([BuildStage(every: 4, days: 7), BuildStage(every: 3, days: 21)], word: "morning"),
                       ["Every 4th morning for 1 week, then every 3rd morning for 3 weeks", "Tendwell asks how your skin is before each move up"])
    }
}
