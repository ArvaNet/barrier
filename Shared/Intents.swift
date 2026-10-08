import AppIntents
import BarrierCore
import Foundation
import UserNotifications
import WidgetKit

enum RoutineChoice: String, AppEnum {
    case evening, morning

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static var caseDisplayRepresentations: [RoutineChoice: DisplayRepresentation] = [
        .evening: "Evening routine",
        .morning: "Morning routine",
    ]

    var slot: Slot { self == .evening ? .pm : .am }

    /// Evening after 2 p.m. (or before the 4 a.m. rollover), morning otherwise.
    static var now: RoutineChoice {
        let h = Calendar.current.component(.hour, from: Date())
        return (h >= 14 || h < dayRolloverHour) ? .evening : .morning
    }
}

/// Log a routine as done without opening the app (widget button, Siri, Shortcuts).
struct MarkRoutineDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark routine done"
    static var description = IntentDescription("Logs your evening or morning routine as done in Barrier.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Routine", default: .evening)
    var routine: RoutineChoice

    init() {}

    init(routine: RoutineChoice) {
        self.routine = routine
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let today = Day.routineDay()
        let slot = routine.slot
        let state = SharedStore.currentState(today: today)
        if let state, state.entry(today, slot)?.status == .done {
            return .result(dialog: "Already logged. Sleep well.")
        }
        SharedStore.appendInbox(InboxItem(day: today, slot: slot, action: .done))
        let ids = ["\(today.iso):\(slot.rawValue):main", "\(today.iso):\(slot.rawValue):nudge"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
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
            return .result(dialog: "Open Barrier to set up your routine first.")
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
