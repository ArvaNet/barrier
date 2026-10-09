import BarrierCore
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

/// Where a deep link or notification tap wants to go.
enum Route: Hashable {
    case today, routine, progress, derm, report, settings
    case ritual(Slot, Day)
}

enum AppTab: Hashable { case today, routine, progress, derm }

struct RitualRequest: Identifiable, Hashable {
    var slot: Slot
    var day: Day
    var id: String { "\(day.iso)-\(slot.rawValue)" }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var undo: (() -> Void)?
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(launch: LaunchOptions.current)

    var state: AppState
    private(set) var now = Date()
    private(set) var today: Day
    var tab: AppTab = .today
    var ritual: RitualRequest?
    var showSettings = false
    var showReport = false
    var toast: Toast?
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// Saved data exists but couldn't be read. Saving is blocked until it's
    /// readable again or the user chooses to start fresh / restore.
    var loadFailed = false
    let launch: LaunchOptions
    let photos = PhotoStore()

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var inboxObserver: DarwinObserver?

    init(launch: LaunchOptions) {
        self.launch = launch
        let now = launch.fixedNow ?? Date()
        self.now = now
        let today = Day.routineDay(now)
        self.today = today
        if launch.demo {
            var s = Presets.demoState(today: today)
            if let theme = launch.theme { s.settings.theme = theme }
            state = s
        } else if launch.fresh {
            state = Presets.blankState(today: today)
        } else {
            switch SharedStore.load() {
            case .loaded(let s): state = s
            case .empty: state = Presets.blankState(today: today)
            case .failed:
                state = Presets.blankState(today: today)
                loadFailed = true
            }
        }
        if !launch.demo {
            inboxObserver = DarwinObserver(name: SharedStore.inboxNotification) { [weak self] in
                Task { @MainActor in self?.ingestInbox() }
            }
        }
    }

    // MARK: Lifecycle

    func becameActive() {
        refreshClock()
        retryLoadIfNeeded()
        ingestInbox()
        let waiting = ritual != nil || RitualMemory.shared.progress.values.contains { ($0.waitEnds ?? .distantPast) > Date() }
        TimerActivity.endStale(keepRunning: waiting)
        Task {
            await refreshNotificationStatus()
            scheduleNotifications(immediately: true)
        }
    }

    func refreshClock() {
        now = launch.fixedNow ?? Date()
        let d = Day.routineDay(now)
        if d != today { today = d }
    }

    /// Before first unlock the file is locked, so a background launch can't read
    /// it. Try again once the app is in front.
    func retryLoadIfNeeded() {
        guard loadFailed, !launch.demo else { return }
        if case .loaded(let s) = SharedStore.load() {
            state = s
            loadFailed = false
        }
    }

    func ingestInbox() {
        guard !launch.demo, !loadFailed else { return }
        let items = SharedStore.drainInbox()
        guard !items.isEmpty else { return }
        update { $0.apply(items, today: today) }
        saveNow()
        for it in items where it.action == .done {
            NotificationService.shared.clearDelivered(day: it.day, slot: it.slot)
            endRitual(it.slot, it.day)
        }
    }

    /// Start fresh after a load failure; the unreadable file is kept aside.
    func acceptFreshStart() {
        loadFailed = false
        saveNow()
    }

    // MARK: Changes

    func update(_ change: (inout AppState) -> Void) {
        change(&state)
        changed()
    }

    private func changed() {
        guard !launch.demo else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
        scheduleNotifications()
    }

    func saveNow() {
        guard !launch.demo, !loadFailed else { return }
        do {
            try SharedStore.saveState(state)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            show("Couldn’t save. Free up some space on your iPhone.")
        }
    }

    func scheduleNotifications(immediately: Bool = false) {
        guard !launch.demo, !loadFailed, state.onboarded else { return }
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            guard let self, !Task.isCancelled else { return }
            await NotificationService.shared.reschedule(self.state)
        }
    }

    func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.shared.status()
    }

    /// A structural plan edit that keeps tonight (and any open question) as it was.
    func editPlan(_ slot: Slot, _ change: (inout AppState) -> Void) {
        update { s in s.editPlan(slot, today: today, change) }
    }

    // MARK: Reading

    func instance(_ slot: Slot, on day: Day? = nil) -> Instance {
        Engine.instance(state, slot: slot, on: day ?? today, today: today)
    }

    func product(_ id: String) -> Product? { state.product(id) }

    var products: [String: Product] {
        Dictionary(state.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Which slot leads Today: the morning until 2 p.m. if it's still open.
    var leadSlot: Slot {
        let h = Calendar.current.component(.hour, from: now)
        let amOpen = state.plan.am.enabled && !state.plan.am.steps.isEmpty && !instance(.am).isResolved
        if !state.plan.pm.enabled || state.plan.pm.steps.isEmpty { return .am }
        return (h >= dayRolloverHour && h < 14 && amOpen) ? .am : .pm
    }

    // MARK: Actions

    func markDone(_ inst: Instance, steps: [String]? = nil, quiet: Bool = false) {
        let prev = state.entry(inst.day, inst.slot)
        update { $0.markDone(inst, steps: steps) }
        NotificationService.shared.clearDelivered(day: inst.day, slot: inst.slot)
        endRitual(inst.slot, inst.day)
        Haptics.success(state.settings.haptics)
        if !quiet {
            show(inst.slot == .pm ? "\(inst.label) done." : "Morning done.") { [weak self] in
                self?.update { $0.restoreEntry(inst.day, inst.slot, to: prev) }
            }
        }
    }

    func markSkipped(_ inst: Instance) {
        let prev = state.entry(inst.day, inst.slot)
        update { $0.markSkipped(inst) }
        NotificationService.shared.clearDelivered(day: inst.day, slot: inst.slot)
        endRitual(inst.slot, inst.day)
        let hold = inst.hasActives ? " Tomorrow picks up where you left off." : ""
        show("Skipped.\(hold)") { [weak self] in self?.update { $0.restoreEntry(inst.day, inst.slot, to: prev) } }
    }

    /// A routine was logged some other way: stop its wait timer and forget its progress.
    func endRitual(_ slot: Slot, _ day: Day) {
        let id = RitualRequest(slot: slot, day: day).id
        guard ritual?.id != id else { return } // the ritual screen handles its own timer
        RitualMemory.shared.progress[id] = nil
        TimerActivity.end()
        NotificationService.shared.cancelTimer()
    }

    func undoEntry(_ inst: Instance) {
        update { $0.clearEntry(inst.day, inst.slot) }
    }

    func setRecovery(_ day: Day, _ slot: Slot, on: Bool) {
        update { $0.setRecovery(day, slot, on: on) }
        if on { show("Tonight is a recovery night. Actives are off.") }
    }

    func show(_ text: String, undo: (() -> Void)? = nil) {
        toastTask?.cancel()
        toast = Toast(text: text, undo: undo)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: undo == nil ? 2_600_000_000 : 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func open(_ route: Route) {
        switch route {
        case .today: tab = .today
        case .routine: tab = .routine
        case .progress: tab = .progress
        case .derm: tab = .derm
        case .report:
            tab = .derm
            showReport = true
        case .settings: showSettings = true
        case .ritual(let slot, let day):
            tab = .today
            ritual = RitualRequest(slot: slot, day: day)
        }
    }

    /// barrier://ritual/pm/2026-10-09, barrier://today, or a notification link.
    func handle(link: String) {
        let parts = link.replacingOccurrences(of: "barrier://", with: "").split(separator: "/").map(String.init)
        guard let head = parts.first else { return }
        switch head {
        case "ritual":
            let slot = parts.count > 1 ? Slot(rawValue: parts[1]) ?? .pm : .pm
            let day = parts.count > 2 ? Day(iso: parts[2]) ?? today : today
            open(.ritual(slot, day))
        case "report": open(.report)
        case "progress": open(.progress)
        case "routine": open(.routine)
        case "derm": open(.derm)
        default: open(.today)
        }
    }

    func finishOnboarding(_ s: AppState) {
        loadFailed = false // setting up again counts as starting fresh
        var s = s
        s.onboarded = true
        update { $0 = s }
        saveNow()
    }

    func resetEverything() {
        loadFailed = false
        photos.deleteAll()
        update { $0 = Presets.blankState(today: today) }
        saveNow()
        Task { await NotificationService.shared.removeAll() }
    }
}

/// Launch arguments, used for screenshots and previews.
struct LaunchOptions {
    var demo = false
    var fresh = false
    var screen: String?
    var theme: ThemeMode?
    var fixedNow: Date?

    static var current: LaunchOptions {
        let args = ProcessInfo.processInfo.arguments
        var o = LaunchOptions()
        o.demo = args.contains("-demo")
        o.fresh = args.contains("-fresh")
        if let i = args.firstIndex(of: "-screen"), i + 1 < args.count { o.screen = args[i + 1] }
        if let i = args.firstIndex(of: "-theme"), i + 1 < args.count { o.theme = ThemeMode(rawValue: args[i + 1]) }
        if let i = args.firstIndex(of: "-hour"), i + 1 < args.count, let h = Int(args[i + 1]) {
            o.fixedNow = Calendar.current.date(bySettingHour: h, minute: 5, second: 0, of: Date())
        }
        return o
    }
}

/// Listens for a Darwin notification (cross-process ping).
final class DarwinObserver {
    private let name: String
    private let handler: () -> Void

    init(name: String, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue().handler()
        }, name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(name as CFString), nil)
    }
}
