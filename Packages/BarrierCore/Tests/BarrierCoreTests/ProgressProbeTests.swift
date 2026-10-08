import XCTest
@testable import BarrierCore

final class ProgressProbeTests: XCTestCase {
    func testProgressComputationsFinish() {
        let today = Day(2026, 10, 8)
        let s = Presets.demoState(today: today)
        let st = Engine.stats(s, today: today)
        XCTAssertGreaterThan(st.nightsDone, 0)
        let rings = Engine.rings(s, today: today)
        XCTAssertFalse(rings.isEmpty)
        let first = today.firstOfMonth
        let end = first.adding(first.daysInMonth - 1)
        let from = max(first, s.plan.createdAt)
        let to = min(end, today.adding(30))
        XCTAssertEqual(Engine.timeline(s, slot: .pm, from: from, to: to, today: today).count, from.days(to: to) + 1)
        XCTAssertEqual(Engine.timeline(s, slot: .am, from: from, to: to, today: today).count, from.days(to: to) + 1)
        _ = Milestones.reached(s, today: today)
    }
}
