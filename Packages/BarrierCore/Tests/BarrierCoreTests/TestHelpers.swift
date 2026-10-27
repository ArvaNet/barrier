@testable import BarrierCore

extension AppState {
    /// The retinoid template as it was before build-ups: every night, no ease-in.
    /// Tests that are about something else start from this.
    mutating func nightlyRetinoid() {
        plan.pm.easeIn = nil
        plan.pm.length = 1
        plan.pm.names = nil
        for i in plan.pm.steps.indices {
            plan.pm.steps[i].on = .all
            plan.pm.steps[i].buildUp = nil
        }
    }

    /// The retinoid template eased in the old way (the whole evening at once).
    mutating func legacyEaseIn(start: Day) {
        nightlyRetinoid()
        plan.pm.easeIn = EaseIn(start: start, phases: Presets.easeInPhases)
    }
}
