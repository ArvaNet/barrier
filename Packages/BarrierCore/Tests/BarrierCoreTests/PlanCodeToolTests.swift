import XCTest
@testable import BarrierCore

/// The clinic pilot page (tools/codes) writes codes with its own encoder, plancode.js.
/// These links were made by that encoder from the page's three examples. If this fails,
/// the page and the app disagree: fix the page, never the printed codes.
final class PlanCodeToolTests: XCTestCase {
    /// "Starting tretinoin" (starting slowly): made by `PlanCode.encode(examples[0].code)` in tools/codes/plancode.js.
    let tretinoin = "barrier://plan/eyJhbSI6eyJzIjpbeyJwIjowfSx7InAiOjJ9LHsiaCI6Ikxhc3Qgc3RlcCBvZiB0aGUgbW9ybmluZy4gQnJvYWQtc3BlY3RydW0uIiwicCI6M31dfSwicCI6W3siayI6ImNsZWFuc2VyIiwibiI6IkdlbnRsZSBjbGVhbnNlciJ9LHsiayI6InJldGlub2lkIiwibiI6IlRyZXRpbm9pbiJ9LHsiayI6Im1vaXN0dXJpemVyIiwibiI6Ik1vaXN0dXJpemVyIn0seyJrIjoic3BmIiwibiI6IlN1bnNjcmVlbiBTUEYgMzArIn1dLCJwbSI6eyJzIjpbeyJwIjowLCJ3IjoyMH0seyJhIjoiUGVhLXNpemUgZm9yIHRoZSB3aG9sZSBmYWNlIiwiYiI6W1szLDE0XSxbMiwxNF1dLCJoIjoiT24gY29tcGxldGVseSBkcnkgc2tpbiIsInAiOjF9LHsicCI6Mn1dfSwidiI6MX0"

    /// "Adapalene every other night".
    let adapalene = "barrier://plan/eyJhbSI6eyJzIjpbeyJwIjowfSx7ImEiOiJUaGluIGxheWVyIG9uIGFmZmVjdGVkIGFyZWFzIiwicCI6Mn0seyJwIjozfSx7ImgiOiJMYXN0IHN0ZXAgb2YgdGhlIG1vcm5pbmcuIEJyb2FkLXNwZWN0cnVtLiIsInAiOjR9XX0sInAiOlt7ImsiOiJjbGVhbnNlciIsIm4iOiJHZW50bGUgY2xlYW5zZXIifSx7ImsiOiJyZXRpbm9pZCIsIm4iOiJBZGFwYWxlbmUifSx7ImsiOiJ0cmVhdG1lbnQiLCJuIjoiQmVuem95bCBwZXJveGlkZSJ9LHsiayI6Im1vaXN0dXJpemVyIiwibiI6Ik1vaXN0dXJpemVyIn0seyJrIjoic3BmIiwibiI6IlN1bnNjcmVlbiBTUEYgMzArIn1dLCJwbSI6eyJsIjoyLCJzIjpbeyJwIjowfSx7ImEiOiJQZWEtc2l6ZSBmb3IgdGhlIHdob2xlIGZhY2UiLCJoIjoiT24gY29tcGxldGVseSBkcnkgc2tpbiIsIm4iOlswXSwicCI6MX0seyJwIjozfV19LCJ2IjoxfQ"

    /// "Back treatment".
    let back = "barrier://plan/eyJib2R5Ijp7Im4iOiJCYWNrIiwicSI6IkFmdGVyIHNob3dlciIsInMiOlt7ImgiOiJJbiB0aGUgc2hvd2VyOiBsZWF2ZSBvbiBhIGZldyBtaW51dGVzLCB0aGVuIHJpbnNlLiBGb2xsb3cgeW91ciBsYWJlbC4iLCJwIjowfV19LCJwIjpbeyJrIjoidHJlYXRtZW50IiwibiI6IkJlbnpveWwgcGVyb3hpZGUgd2FzaCJ9XSwidiI6MX0"

    func testThePageWritesWhatTheAppReads() throws {
        for link in [tretinoin, adapalene, back] {
            let code = try PlanCode(link: link)
            // The app writes the same text back, so the page's encoder is the app's, byte for byte.
            XCTAssertEqual(code.link, link)
            XCTAssertEqual(try PlanCode(link: code.link), code)
        }
    }

    func testStartingTretinoin() throws {
        let code = try PlanCode(link: tretinoin)
        XCTAssertNil(code.clinic)
        XCTAssertNil(code.ifIrritated)
        XCTAssertEqual(code.slots, [.pm, .am])
        XCTAssertEqual(code.products.map(\.name), ["Gentle cleanser", "Tretinoin", "Moisturizer", "Sunscreen SPF 30+"])
        XCTAssertEqual(code.products.map(\.kind), [.cleanser, .retinoid, .moisturizer, .spf])

        let pm = try XCTUnwrap(code.routines[.pm])
        XCTAssertEqual(pm.length, 1)
        XCTAssertEqual(pm.steps.count, 3)
        XCTAssertEqual(pm.steps[0], PlanCode.Line(product: 0, waitMin: 20))
        XCTAssertEqual(pm.steps[1], PlanCode.Line(product: 1, amount: "Pea-size for the whole face", how: "On completely dry skin",
                                                  buildUp: Presets.buildUpStages))

        let am = try XCTUnwrap(code.routines[.am])
        XCTAssertEqual(am.steps.count, 3)
        XCTAssertEqual(am.steps[2], PlanCode.Line(product: 3, how: "Last step of the morning. Broad-spectrum."))
        XCTAssertTrue(am.steps.allSatisfy { $0.buildUp.isEmpty })
    }

    func testAdapaleneEveryOtherNight() throws {
        let code = try PlanCode(link: adapalene)
        XCTAssertEqual(code.slots, [.pm, .am])
        XCTAssertEqual(code.products.map(\.kind), [.cleanser, .retinoid, .treatment, .moisturizer, .spf])

        let pm = try XCTUnwrap(code.routines[.pm])
        XCTAssertEqual(pm.length, 2)
        XCTAssertEqual(pm.steps.count, 3)
        XCTAssertEqual(pm.steps[1], PlanCode.Line(product: 1, amount: "Pea-size for the whole face", how: "On completely dry skin", on: .nights([0])))
        XCTAssertEqual(pm.steps[1].buildUp, [])

        let am = try XCTUnwrap(code.routines[.am])
        XCTAssertEqual(am.steps.count, 4)
        XCTAssertEqual(am.steps[1], PlanCode.Line(product: 2, amount: "Thin layer on affected areas"))
    }

    func testBackTreatment() throws {
        let code = try PlanCode(link: back)
        XCTAssertEqual(code.slots, [.body])
        XCTAssertEqual(code.products, [PlanCode.Item(name: "Benzoyl peroxide wash", kind: .treatment)])
        let body = try XCTUnwrap(code.routines[.body])
        XCTAssertEqual(body.name, "Back")
        XCTAssertEqual(body.cue, "After shower")
        XCTAssertEqual(body.length, 1)
        XCTAssertEqual(body.steps, [PlanCode.Line(product: 0, how: "In the shower: leave on a few minutes, then rinse. Follow your label.")])
    }
}
