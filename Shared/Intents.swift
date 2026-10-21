import AppIntents
import BarrierCore
import Foundation
import UserNotifications
import WidgetKit

enum RoutineChoice: String, AppEnum {
    case evening, morning, body

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static var caseDisplayRepresentations: [RoutineChoice: DisplayRepresentation] = [
        .evening: "Evening routine",
        .morning: "Morning routine",
        .body: "Body routine",
    ]

    var slot: Slot {
        switch self {
        case .evening: return .pm
        case .morning: return .am
        case .body: return .body
        }
    }

    /// Evening after 2 p.m. (or before the 4 a.m. rollover), morning otherwise.
    static var now: RoutineChoice {
        let h = Calendar.current.component(.hour, from: Date())
        return (h >= 14 || h < dayRolloverHour) ? .evening : .morning
    }

    init(slot: Slot) {
        switch slot {
        case .pm: self = .evening
        case .am: self = .morning
        case .body: self = .body
        }
    }

    /// "I did my routine" with no routine named: the current face routine,
    /// or the body routine when that's what is set up for this time of day.
    static func defaultSlot(_ state: AppState?) -> Slot {
        let preferred = now.slot
        guard let state else { return preferred }
        let active = state.plan.activeSlots
        if active.contains(preferred) { return preferred }
        if active.contains(.body) && (now == .evening || !active.contains(.am)) { return .body }
        return active.first ?? preferred
    }
}

/// Log a routine as done without opening the app (widget button, Siri, Shortcuts).
struct MarkRoutineDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark routine done"
    static var description = IntentDescription("Logs your evening or morning routine as done in Tendwell.")
    static var openAppWhenRun: Bool = false

    /// Empty means "whichever routine is current" (morning before 2 p.m.).
    @Parameter(title: "Routine")
    var routine: RoutineChoice?

    init() {}

    init(routine: RoutineChoice?) {
        self.routine = routine
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let today = Day.routineDay()
        let state = SharedStore.currentState(today: today)
        let slot = routine?.slot ?? RoutineChoice.defaultSlot(state)
        if let state, !state.plan.activeSlots.contains(slot) {
            return .result(dialog: "That routine isn’t set up in Tendwell.")
        }
        if let state, state.entry(today, slot)?.status == .done {
            switch slot {
            case .pm: return .result(dialog: "Already logged. Sleep well.")
            case .am: return .result(dialog: "Already logged for this morning.")
            case .body: return .result(dialog: "Already logged for today.")
            }
        }
        SharedStore.appendInbox(InboxItem(day: today, slot: slot, action: .done))
        let ids = ["\(today.iso):\(slot.rawValue):main", "\(today.iso):\(slot.rawValue):nudge", "snooze:\(today.iso):\(slot.rawValue)"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        WidgetCenter.shared.reloadAllTimelines()
        if let state {
            let next = Engine.instance(state, slot: slot, on: today.adding(1), today: today)
            if slot == .pm && !next.steps.isEmpty {
                return .result(dialog: "Done. Tomorrow is \(next.label.lowercased()).")
            }
        }
        return .result(dialog: "Done. Nice work.")
    }
}

/// "What's tonight?"
struct TonightIntent: AppIntent {
    static var title: LocalizedStringResource = "What’s tonight"
    static var description = IntentDescription("Tells you tonight’s routine.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let today = Day.routineDay()
        guard let state = SharedStore.currentState(today: today), state.onboarded else {
            return .result(dialog: "Open Tendwell to set up your routine first.")
        }
        let active = state.plan.activeSlots
        // No evening routine: answer for the body routine if there is one.
        if !active.contains(.pm) {
            guard active.contains(.body) else { return .result(dialog: "There’s no evening routine set up in Tendwell.") }
            let body = Engine.instance(state, slot: .body, on: today, today: today)
            if body.status == .done { return .result(dialog: "\(body.label) is done for today.") }
            if body.steps.isEmpty { return .result(dialog: "Nothing for your \(body.label.lowercased()) today.") }
            let list = ListFormatter.localizedString(byJoining: body.steps.map(\.product.name))
            return .result(dialog: "\(body.label) today: \(list).")
        }
        let inst = Engine.instance(state, slot: .pm, on: today, today: today)
        if inst.status == .done {
            let next = Engine.instance(state, slot: .pm, on: today.adding(1), today: today)
            return .result(dialog: "Tonight is done. Tomorrow is \(next.label.lowercased()).")
        }
        let names = inst.steps.map(\.product.name)
        let list = ListFormatter.localizedString(byJoining: names)
        return .result(dialog: "Tonight is \(inst.label.lowercased()): \(list).")
    }
}
