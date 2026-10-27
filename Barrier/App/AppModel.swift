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
    let photos: PhotoStore

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var inboxObserver: DarwinObserver?

    init(launch: LaunchOptions) {
        self.launch = launch
        self.photos = PhotoStore(demo: launch.sandbox)
        let now = launch.fixedNow ?? Date()
        self.now = now
        let today = Day.routineDay(now)
        self.today = today
        if launch.demo {
            var s = Presets.demoState(today: today)
            if let theme = launch.theme { s.settings.theme = theme }
            state = s
        } else if launch.starter {
            // Day one after onboarding with "Starting a retinoid": what a new user sees.
            var s = Presets.apply(.retinoid, to: Presets.blankState(today: today), today: today)
            s.onboarded = true
            if let theme = launch.theme { s.settings.theme = theme }
            // `-screen today-moveup`: two weeks into the retinoid's first stage, so Tendwell asks.
            if launch.screen == "today-moveup" {
                for i in s.plan.pm.steps.indices where s.plan.pm.steps[i].buildUp != nil {
                    s.plan.pm.steps[i].buildUp?.start = today.adding(-15)
                }
            }
            // `-screen filled-…`: three weeks on paper before Barrier, filled in.
            if launch.screen?.hasPrefix("filled-") == true {
                s.recordPlan(today: today)
                s.fillIn(since: today.adding(-21), missed: [.pm: [today.adding(-9), today.adding(-8)], .am: [today.adding(-4)]], today: today)
                s.checkIn(today.adding(-10), feel: [.dry, .flaky])
            }
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
        // Saves from before the change log: today's routine is where it starts (today's edits still count).
        if state.onboarded && state.history.isEmpty { state.recordPlan(today: today, start: true) }
        migrateOldSave()
        if !launch.sandbox { Self.pruneMigrationCopies(today: today) }
        if launch.demo {
            DemoPhotos.ensure(state.photos, in: photos)
        } else {
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
        guard loadFailed, !launch.sandbox else { return }
        if case .loaded(let s) = SharedStore.load() {
            state = s
            loadFailed = false
            if state.onboarded && state.history.isEmpty { state.recordPlan(today: today, start: true) }
            migrateOldSave()
        }
    }

    /// Pre-conversion copies are a short-term safety net, not an archive.
    private static func pruneMigrationCopies(today: Day) {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasPrefix("before-build-up-") && name.hasSuffix(".json") {
            let iso = String(name.dropFirst("before-build-up-".count).dropLast(".json".count))
            if let d = Day(iso: iso), d.days(to: today) > 30 { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
        }
    }

    /// Saves from before per-product build-ups eased in a whole routine at once.
    /// That ease-in moves onto its treatments, keeping tonight and the next nights.
    private func migrateOldSave() {
        let before = state
        guard state.migrateEaseIn(today: today) else { return }
        // The save as it was, kept in the app's own Documents (reachable from Xcode) in case it's ever needed.
        // Same protection as the real save; it's removed after 30 days (see pruneMigrationCopies).
        if !launch.sandbox && !loadFailed, let data = try? StateCoder.encode(before) {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("before-build-up-\(today.iso).json")
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if state.onboarded { state.recordPlan(today: today) }
        if !launch.sandbox && !loadFailed { saveNow() }
    }

    func ingestInbox() {
        guard !launch.sandbox, !loadFailed else { return }
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
        // The change log: one entry per day the routine changed.
        if state.onboarded { state.recordPlan(today: today) }
        changed()
    }

    private func changed() {
        guard !launch.sandbox else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
        scheduleNotifications()
    }

    func saveNow() {
        guard !launch.sandbox, !loadFailed else { return }
        do {
            try SharedStore.saveState(state)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            show("Couldn’t save. Free up some space on your iPhone.")
        }
    }

    func scheduleNotifications(immediately: Bool = false) {
        guard !launch.sandbox, !loadFailed, state.onboarded else { return }
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
        let active = state.plan.activeSlots
        let hasAM = active.contains(.am)
        let hasPM = active.contains(.pm)
        // Only a body routine set up: it leads.
        if !hasAM && !hasPM { return active.contains(.body) ? .body : .pm }
        let h = Calendar.current.component(.hour, from: now)
        let amOpen = hasAM && !instance(.am).isResolved
        // Morning only, plus a body routine: once the morning is done, the body leads.
        if !hasPM { return (amOpen || !active.contains(.body)) ? .am : .body }
        return (h >= dayRolloverHour && h < 14 && amOpen) ? .am : .pm
    }

    /// The other routines, shown as rows under the lead card, earliest first.
    /// The body routine is left out on its off days (nothing due, nothing logged).
    var otherSlots: [Slot] {
        let lead = leadSlot
        return state.plan.activeSlots
            .filter { $0 != lead }
            .filter { slot in
                guard slot == .body else { return true }
                let inst = instance(.body)
                return !inst.steps.isEmpty || inst.entry != nil
            }
            .sorted { state.plan[$0].time < state.plan[$1].time }
    }

    /// The body routine is set up with at least one step.
    var hasBodyRoutine: Bool { state.plan.activeSlots.contains(.body) }

    /// What the body area is called: the body routine's name ("Back"), or "Body" without one.
    var bodyAreaName: String { hasBodyRoutine ? state.plan.body.displayName : "Body" }

    // MARK: Actions

    func markDone(_ inst: Instance, steps: [String]? = nil, quiet: Bool = false) {
        let prev = state.entry(inst.day, inst.slot)
        update { $0.markDone(inst, steps: steps) }
        NotificationService.shared.clearDelivered(day: inst.day, slot: inst.slot)
        endRitual(inst.slot, inst.day)
        Haptics.success(state.settings.haptics)
        if !quiet {
            show(inst.slot == .am ? "Morning done." : "\(inst.label) done.") { [weak self] in
                self?.update { $0.restoreEntry(inst.day, inst.slot, to: prev) }
            }
        }
    }

    func markSkipped(_ inst: Instance) {
        let prev = state.entry(inst.day, inst.slot)
        update { $0.markSkipped(inst) }
        NotificationService.shared.clearDelivered(day: inst.day, slot: inst.slot)
        endRitual(inst.slot, inst.day)
        let hold = inst.hasActives && inst.cycleLen > 1 ? " Next time picks up where you left off." : ""
        show("Skipped.\(hold)") { [weak self] in self?.update { $0.restoreEntry(inst.day, inst.slot, to: prev) } }
    }

    /// A routine was logged some other way: stop its wait timer and forget its progress.
    func endRitual(_ slot: Slot, _ day: Day) {
        let id = RitualRequest(slot: slot, day: day).id
        // Only this routine's countdown: another routine's wait keeps running.
        if ritual?.id != id { RitualMemory.shared.progress[id] = nil }
        TimerActivity.end(ritualID: id)
        NotificationService.shared.cancelTimer(ritualID: id)
    }

    /// End a pause or a procedure's break early, and say what happens next.
    func endPause(_ pause: Pause) {
        let proc = pause.procedureID.flatMap { id in state.procedures.first { $0.id == id } }
        update { $0.endPause(pause.id, today: today) }
        guard let proc else {
            show(pause.from <= today ? "Welcome back. The plan is on again." : "Break removed.")
            return
        }
        // Ended in the days before: the clinic's break from the procedure day on stays.
        if let kept = state.pauses.first(where: { $0.procedureID == proc.id && $0.from > today }) {
            show("Actives back on until \(kept.from.relative(to: today, evening: false)). The break after \(proc.name) stays.")
        } else {
            show(pause.from <= today ? "Actives are back on." : "Break removed.")
        }
    }

    func undoEntry(_ inst: Instance) {
        update { $0.clearEntry(inst.day, inst.slot) }
    }

    func setRecovery(_ day: Day, _ slot: Slot, on: Bool) {
        update { $0.setRecovery(day, slot, on: on) }
        if on {
            show(slot == .body ? "\(state.plan.body.displayName): gentle day, treatment left out." : "Tonight is a recovery night. Actives are off.")
        }
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
    var starter = false
    /// Demo and starter states are never saved and never touch real photos or reminders.
    var sandbox: Bool { demo || starter }
    var screen: String?
    var theme: ThemeMode?
    var fixedNow: Date?

    static var current: LaunchOptions {
        let args = ProcessInfo.processInfo.arguments
        var o = LaunchOptions()
        o.demo = args.contains("-demo")
        o.fresh = args.contains("-fresh")
        o.starter = args.contains("-starter")
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
