import Foundation

// Every change to the state goes through these, so the app, the widget and
// the notification actions all log nights the same way.

public extension AppState {
    private func entryIndex(_ day: Day, _ slot: Slot) -> Int? {
        log.lastIndex { $0.day == day && $0.slot == slot }
    }

    private mutating func upsert(_ e: Entry) {
        log.removeAll { $0.day == e.day && $0.slot == e.slot }
        log.append(e)
        log.sort { a, b in a.day == b.day ? a.slot.rawValue < b.slot.rawValue : a.day < b.day }
    }

    func entry(_ day: Day, _ slot: Slot) -> Entry? {
        entryIndex(day, slot).map { log[$0] }
    }

    mutating func markDone(_ inst: Instance, steps: [String]? = nil, at: Date = Date()) {
        let prev = entry(inst.day, inst.slot)
        var e = Entry(day: inst.day, slot: inst.slot, status: .done, pos: inst.pos, label: inst.label, hue: inst.hue, steps: steps, at: at)
        if prev?.recovery == true { e.recovery = true }
        upsert(e)
    }

    /// Log a slot as done from outside the app (notification, widget, Siri).
    mutating func markDone(_ slot: Slot, on day: Day, today: Day, at: Date = Date()) {
        if entry(day, slot)?.status == .done { return }
        let inst = Engine.instance(self, slot: slot, on: day, today: today)
        markDone(inst, at: at)
    }

    mutating func markSkipped(_ inst: Instance, at: Date = Date()) {
        let prev = entry(inst.day, inst.slot)
        var e = Entry(day: inst.day, slot: inst.slot, status: .skipped, pos: inst.pos, label: inst.label, hue: inst.hue, at: at)
        if prev?.recovery == true { e.recovery = true }
        upsert(e)
    }

    mutating func markSkipped(_ slot: Slot, on day: Day, today: Day) {
        let inst = Engine.instance(self, slot: slot, on: day, today: today)
        markSkipped(inst)
    }

    /// Put back exactly what was logged before (for Undo).
    mutating func restoreEntry(_ day: Day, _ slot: Slot, to previous: Entry?) {
        log.removeAll { $0.day == day && $0.slot == slot }
        if let previous { upsert(previous) }
    }

    mutating func clearEntry(_ day: Day, _ slot: Slot) {
        guard let i = entryIndex(day, slot) else { return }
        if log[i].recovery == true {
            // Keep the recovery choice, forget the done/skip.
            log[i].status = .open
            log[i].steps = nil
        } else {
            log.remove(at: i)
        }
    }

    mutating func setRecovery(_ day: Day, _ slot: Slot, on: Bool) {
        let prev = entry(day, slot)
        if on {
            var e = prev ?? Entry(day: day, slot: slot, status: .open)
            e.recovery = true
            e.label = slot == .pm ? "Recovery night" : "Gentle morning"
            e.hue = .sage
            upsert(e)
        } else if let p = prev {
            if p.status == .open {
                log.removeAll { $0.day == day && $0.slot == slot }
            } else {
                var e = p
                e.recovery = nil
                upsert(e)
            }
        }
    }

    mutating func checkIn(_ day: Day, feel: [Feeling], note: String? = nil) {
        checkins.removeAll { $0.day == day }
        if feel.isEmpty && (note ?? "").isEmpty { return }
        checkins.append(CheckIn(day: day, feel: feel, note: note?.isEmpty == true ? nil : note))
        checkins.sort { $0.day < $1.day }
    }

    func checkIn(on day: Day) -> CheckIn? { checkins.first { $0.day == day } }

    mutating func addPause(from: Day, to: Day, reason: PauseReason) {
        pauses.append(Pause(from: min(from, to), to: max(from, to), reason: reason))
    }

    /// End a pause so the routine is back on today.
    mutating func endPause(_ id: String, today: Day) {
        guard let i = pauses.firstIndex(where: { $0.id == id }) else { return }
        if today <= pauses[i].from {
            pauses.remove(at: i)
        } else {
            pauses[i].to = today.adding(-1)
        }
    }

    mutating func upsertProduct(_ p: Product) {
        if let i = products.firstIndex(where: { $0.id == p.id }) { products[i] = p } else { products.append(p) }
    }

    /// Remove a product and every step that uses it.
    mutating func removeProduct(_ id: String) {
        products.removeAll { $0.id == id }
        plan.am.steps.removeAll { $0.productId == id }
        plan.pm.steps.removeAll { $0.productId == id }
    }

    /// Products no step uses any more.
    mutating func pruneOrphanProducts() {
        let used = Set((plan.am.steps + plan.pm.steps).map(\.productId))
        products.removeAll { !used.contains($0.id) }
    }

    /// Make a structural plan edit without changing what tonight is.
    /// History before the edit keeps its meaning: the replay restarts at
    /// today (or at last night, if last night still needs an answer).
    mutating func editPlan(_ slot: Slot, today: Day, _ change: (inout AppState) -> Void) {
        let tonight = Engine.instance(self, slot: slot, on: today, today: today)
        let pending = Engine.needsReconcile(self, today: today).first { $0.slot == slot }
        change(&self)
        let day = pending?.day ?? today
        let pos = pending?.pos ?? tonight.pos
        let cl = Engine.cycleLen(plan[slot], on: day)
        plan[slot].anchor = Anchor(day: day, pos: max(0, min(pos, cl - 1)))
    }

    /// After a structural edit, restart the replay today at a valid position,
    /// so history before today keeps its meaning.
    mutating func rebase(_ slot: Slot, today: Day, keeping instance: Instance? = nil) {
        let cl = Engine.cycleLen(plan[slot], on: today)
        let pos = instance.map { min($0.pos, cl - 1) } ?? 0
        plan[slot].anchor = Anchor(day: today, pos: max(0, pos))
    }

    mutating func dismiss(_ id: String) {
        if !dismissed.contains(id) { dismissed.append(id) }
    }

    /// Fold in "Done" taps recorded by notifications or the widget.
    mutating func apply(_ inbox: [InboxItem], today: Day) {
        for it in inbox.sorted(by: { $0.at < $1.at }) {
            switch it.action {
            case .done: markDone(it.slot, on: it.day, today: today, at: it.at)
            case .skip:
                if entry(it.day, it.slot) == nil { markSkipped(it.slot, on: it.day, today: today) }
            }
        }
    }
}

/// A logged tap that happened outside the app's main process.
public struct InboxItem: Codable, Hashable, Sendable {
    public enum Action: String, Codable, Sendable { case done, skip }
    public var day: Day
    public var slot: Slot
    public var action: Action
    public var at: Date

    public init(day: Day, slot: Slot, action: Action, at: Date = Date()) {
        self.day = day
        self.slot = slot
        self.action = action
        self.at = at
    }
}
