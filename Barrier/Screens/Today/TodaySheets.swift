import BarrierCore
import SwiftUI

// MARK: - Not tonight

struct NotTonightSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var inst: Instance
    @State private var showPause = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                Section {
                    option(skipTitle, detail: skipDetail, symbol: "moon.zzz") {
                        model.markSkipped(inst)
                        dismiss()
                    }
                    if inst.slot != .am && inst.hasActives && inst.rest == nil {
                        option(inst.slot.isBody ? "Skin’s irritated: gentle day" : "Skin’s irritated: recovery night",
                               detail: inst.slot.isBody ? "Leaves out the treatment today. Your face routine isn’t affected." : "Drops the actives tonight. Your rotation waits.",
                               symbol: "leaf") {
                            model.setRecovery(inst.day, inst.slot, on: true)
                            dismiss()
                        }
                    }
                    option("Pause the plan…", detail: inst.slot.isBody
                           ? "Pauses your face routines too. Basics only until you’re back."
                           : "Traveling, a procedure, or a break. Basics only until you’re back.", symbol: "pause.circle") {
                        showPause = true
                    }
                }
                if !inst.slot.isBody, let derm = model.state.plan.ifIrritated, !derm.isEmpty {
                    Section("Your dermatologist said") {
                        Text(derm).font(.subheadline)
                    }
                }
                }
                .rows()
            }
            .barrierList()
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle("\(inst.slot.notNow)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showPause) {
                PauseSheet { dismiss() }.barrier(model).presentationDetents([.medium])
            }
        }
    }

    private var skipTitle: String {
        switch inst.slot {
        case .pm: return "Skip tonight"
        case .am: return "Skip this morning"
        case .body, .body2: return "Skip today"
        }
    }

    private var skipDetail: String {
        if inst.hasActives && inst.cycleLen > 1 {
            return inst.slot.isBody ? "Next time picks up where you left off." : "Next time picks up \(inst.label.lowercased()) where you left off."
        }
        return inst.slot == .pm && !inst.hasActives ? "Rest nights still count." : "It’s logged as skipped. No streaks to lose."
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Palette.ink2).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(detail).font(.footnote).foregroundStyle(Palette.ink3)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct PauseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void = {}
    @State private var reason: PauseReason = .travel
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(4 * 86400)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Why", selection: $reason) {
                        ForEach(PauseReason.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("Until", selection: $to, in: from..., displayedComponents: .date)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reminders switch to the basics (cleanse, moisturize, sunscreen). When the pause ends, your rotation continues exactly where it stopped.")
                        if reason == .procedure {
                            Text("Booked a procedure? Add it under Derm, Procedures instead: it sets the break from your clinic’s dates, reminds you the evening before and pairs your before and after photos.")
                        }
                    }
                }
                .rows()
            }
            .barrierList()
            .navigationTitle("Pause the plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pause") {
                        let a = Day(date: from)
                        let b = Day(date: to)
                        model.update { $0.addPause(from: a, to: b, reason: reason) }
                        model.show("Paused until \(max(a, b).short).")
                        dismiss()
                        onDone()
                    }
                    .tint(Palette.accent)
                }
            }
        }
    }
}

// MARK: - A day in detail (from the week strip or calendar)

struct DayDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var day: Day
    @State private var editing: ProcedureEdit?

    var body: some View {
        NavigationStack {
            List {
                Group {
                ForEach(Procedures.on(model.state, day)) { p in
                    Section("Procedure") {
                        Button {
                            editing = ProcedureEdit(procedure: p, isNew: false)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(.headline).foregroundStyle(Palette.ink)
                                let info = [p.spot, p.clinic].compactMap { $0 }.joined(separator: " · ")
                                if !info.isEmpty { Text(info).font(.subheadline).foregroundStyle(.secondary) }
                                if let n = p.note { Text(n).font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                ForEach(Slot.ordered, id: \.self) { slot in
                    let sp = model.state.plan[slot]
                    // The body routine starts later than the plan: no empty sections before it.
                    let started = day >= model.state.plan.createdAt && (!slot.isBody || day >= sp.anchor.day)
                    if (sp.enabled && !sp.steps.isEmpty && started) || model.state.entry(day, slot) != nil {
                        section(slot)
                    }
                }
                ForEach(Area.allCases) { area in
                    let c = model.state.checkIn(on: day, area: area)
                    // Any day up to today can say how the skin was (missed days, the weeks before Barrier).
                    let canLog = day <= model.today && (area == .face || !model.state.plan.bodySlots.isEmpty)
                    if c != nil || canLog {
                        Section(area == .face ? "Skin" : "Skin · \(model.bodyAreaName)") {
                            if canLog {
                                SkinChips(day: day, area: area)
                            } else if let c {
                                Text(c.feel.map(\.label).joined(separator: ", "))
                            }
                            if let n = c?.note { Text(n).foregroundStyle(.secondary) }
                        }
                    }
                }
                if model.state.photos.contains(where: { $0.day == day }) {
                    Section {
                        Label("Progress photo taken", systemImage: "camera")
                    }
                }
                }
                .rows()
            }
            .barrierList()
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle(day.long)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { e in ProcedureSheet(edit: e).barrier(model) }
        }
    }

    @ViewBuilder
    private func section(_ slot: Slot) -> some View {
        let inst = model.instance(slot, on: day)
        Section {
            HStack(spacing: 10) {
                HueDot(hue: inst.hue, size: 12, hollow: !inst.isDone)
                Text(inst.label.isEmpty ? slot.name(model.state.plan) : inst.label).font(.headline)
                Spacer()
                Text(statusText(inst)).font(.subheadline).foregroundStyle(.secondary)
            }
            // The same separator edge as the step rows below.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            ForEach(inst.steps, id: \.step.id) { s in
                // Done: every step, or the ones ticked in a partial routine.
                let done = inst.isDone && (inst.entry?.steps.map { $0.contains(s.step.id) } ?? true)
                HStack {
                    Text(s.product.name)
                    Spacer()
                    if let a = s.step.amount { Text(a).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                    if done {
                        Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
                            .accessibilityLabel("Done")
                    }
                }
            }
            if inst.steps.isEmpty && inst.entry == nil && inst.status != .off {
                Text("Nothing due that day.").foregroundStyle(.secondary)
            } else if day <= model.today && inst.status != .off {
                if inst.isResolved {
                    Button("Clear what was logged", role: .destructive) { model.undoEntry(inst) }
                } else {
                    Button("Mark done") { model.markDone(inst, quiet: true) }
                    Button("Mark skipped") { model.markSkipped(inst) }
                }
            }
        } header: {
            Text(slot.name(model.state.plan))
        }
    }

    private func statusText(_ inst: Instance) -> String {
        switch inst.status {
        case .done: return "Done"
        case .skipped: return "Skipped"
        case .pending: return "Today"
        case .future: return "Planned"
        case .unlogged: return "Not logged"
        case .off: return ""
        }
    }
}

// MARK: - How the skin was, on any day

/// The check-in chips for one day and area; a tap saves.
struct SkinChips: View {
    @Environment(AppModel.self) private var model
    var day: Day
    var area: Area

    var body: some View {
        let existing = model.state.checkIn(on: day, area: area)
        SkinPicker(area: area, selected: Set(existing?.feel ?? [])) { set in
            let ordered = Feeling.allCases.filter { set.contains($0) }
            model.update { $0.checkIn(day, feel: ordered, note: existing?.note, area: area) }
        }
        .padding(.vertical, 6)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

// MARK: - The weeks before Barrier

/// For someone who followed the routine before setting up Barrier: since when, and which
/// days were missed. Every other day counts as done, marked as filled in afterwards.
struct FillInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var missed: [Slot: Set<Day>] = [:]
    /// Days done without some products: [routine: [day: product ids]].
    @State private var skipped: [Slot: [Day: Set<String>]] = [:]
    @State private var slot: Slot = .pm
    @State private var mode: Mode = .missed
    @State private var productID: String?
    /// The days the chosen product was due, given what's marked so far.
    @State private var due: Set<Day> = []

    enum Mode: Hashable { case missed, product }

    init(start: Day) {
        _start = State(initialValue: start.date())
    }

    /// Whether there's anything before the plan to fill in.
    static func available(_ s: AppState, today: Day) -> Bool {
        s.plan.createdAt > AppState.fillInEarliest(today: today) && !s.fillInSlots().isEmpty
    }

    /// Three weeks back by default, inside the window.
    static func suggestedStart(_ s: AppState, today: Day) -> Day {
        max(AppState.fillInEarliest(today: today), s.plan.createdAt.adding(-21))
    }

    var body: some View {
        let s = model.state
        let earliest = AppState.fillInEarliest(today: model.today)
        let last = max(earliest, s.plan.createdAt.adding(-1))
        let days = s.fillInDays(since: Day(date: start))
        let slots = s.fillInSlots()
        let shown = slots.contains(slot) ? slot : (slots.first ?? .pm)
        let off = (missed[shown] ?? []).filter { days.contains($0) }
        let products = productsIn(shown)
        let chosen = products.first { $0.id == productID } ?? products.first
        let leftOut = (skipped[shown] ?? [:]).filter { days.contains($0.key) && !off.contains($0.key) }
        NavigationStack {
            List {
                Group {
                    Section {
                        DatePicker("Following it since", selection: $start, in: earliest.date()...last.date(), displayedComponents: .date)
                    } footer: {
                        Text("Every day from then until \(last.short) counts as done. Mark only what was different.")
                    }
                    Section {
                        if slots.count > 1 {
                            Picker("Routine", selection: $slot) {
                                ForEach(slots, id: \.self) { Text($0.name(s.plan)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        Picker("Tap a day to mark", selection: $mode) {
                            Text("Missed it all").tag(Mode.missed)
                            Text("Left a product out").tag(Mode.product)
                        }
                        .pickerStyle(.segmented)
                        if mode == .product {
                            FlowLayout(spacing: 8) {
                                ForEach(products) { p in
                                    Chip(title: p.shortName, selected: p.id == chosen?.id, hue: p.kind.hue) { productID = p.id }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        FillInGrid(days: days, state: { d in cellState(d, slot: shown, off: off, chosen: chosen) }) { d in
                            tap(d, slot: shown, chosen: chosen)
                        }
                    } header: {
                        Text(summary(shown, days: days, off: off, leftOut: leftOut))
                    } footer: {
                        Text(mode == .product
                             ? "Days with a dot had \(chosen?.shortName ?? "it") due. Tap the ones you left it out; the rest of the routine still counts."
                             : "Saved as filled in afterwards, and your report says so. Change any day later from the calendar in Progress.")
                    }
                }
                .rows()
            }
            .barrierList()
            .navigationTitle("Before Tendwell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .tint(Palette.accent)
                        .disabled(days.isEmpty)
                }
            }
            .task(id: dueKey(shown, chosen)) {
                guard mode == .product, let p = chosen else { due = []; return }
                due = model.state.fillInDue(shown, productID: p.id, since: Day(date: start), missed: missed, today: model.today)
            }
        }
    }

    /// Treatments first: they're what gets left out.
    private func productsIn(_ slot: Slot) -> [Product] {
        let ps = model.state.plan[slot].steps.compactMap { model.product($0.productId) }
        var seen = Set<String>()
        return ps.filter { seen.insert($0.id).inserted }.sorted { ($0.kind.isActive ? 0 : 1) < ($1.kind.isActive ? 0 : 1) }
    }

    private func dueKey(_ slot: Slot, _ p: Product?) -> String {
        let m = (missed[slot] ?? []).map(\.iso).sorted().joined()
        return "\(mode)|\(slot.rawValue)|\(p?.id ?? "")|\(Day(date: start).iso)|\(m)"
    }

    private func cellState(_ d: Day, slot: Slot, off: Set<Day>, chosen: Product?) -> FillInGrid.CellState {
        let left = skipped[slot]?[d] ?? []
        if off.contains(d) { return .init(kind: .missed, dim: mode == .product) }
        guard mode == .product, let p = chosen else {
            return .init(kind: left.isEmpty ? .done : .partial, hue: nil)
        }
        // Product mode: dots on the days it was due (all days while that's being worked out).
        let isDue = due.isEmpty || due.contains(d)
        return .init(kind: left.isEmpty ? .done : .partial, hue: isDue ? (p.kind.hue ?? .sage) : nil,
                     dotFilled: !left.contains(p.id), dim: !isDue)
    }

    private func tap(_ d: Day, slot: Slot, chosen: Product?) {
        switch mode {
        case .missed:
            var m = missed[slot] ?? []
            if m.contains(d) { m.remove(d) } else { m.insert(d) }
            missed[slot] = m
        case .product:
            guard let p = chosen, !(missed[slot] ?? []).contains(d), due.isEmpty || due.contains(d) else { return }
            var bySlot = skipped[slot] ?? [:]
            var left = bySlot[d] ?? []
            if left.contains(p.id) { left.remove(p.id) } else { left.insert(p.id) }
            bySlot[d] = left.isEmpty ? nil : left
            skipped[slot] = bySlot
        }
        Haptics.tap(model.state.settings.haptics)
    }

    /// "Evening · 18 of 20 done · Adapalene left out 2×".
    private func summary(_ slot: Slot, days: [Day], off: Set<Day>, leftOut: [Day: Set<String>]) -> String {
        var parts = ["\(slot.name(model.state.plan))", "\(days.count - off.count) of \(days.count) done"]
        var counts: [String: Int] = [:]
        for ids in leftOut.values { for id in ids { counts[id, default: 0] += 1 } }
        for (id, n) in counts.sorted(by: { $0.key < $1.key }) {
            if let p = model.product(id) { parts.append("\(p.shortName) left out \(n)×") }
        }
        return parts.joined(separator: " · ")
    }

    private func save() {
        let from = Day(date: start)
        let n = model.state.fillInDays(since: from).count
        let before = model.state
        let m = model
        let skip = skipped
        m.update { $0.fillIn(since: from, missed: missed, skipped: skip, today: m.today) }
        m.show("Filled in \(n) day\(n == 1 ? "" : "s") from \(from.short).") {
            m.update { $0 = before }
        }
        Haptics.success(model.state.settings.haptics)
        dismiss()
    }
}

/// The days as a calendar, Monday first: done in sage, missed dashed, and in product
/// mode a dot for each day the product was due (hollow when it was left out).
struct FillInGrid: View {
    struct CellState {
        enum Kind { case done, partial, missed }
        var kind: Kind
        /// The product's dot, in product mode.
        var hue: Hue? = nil
        var dotFilled = true
        var dim = false
    }

    var days: [Day]
    var state: (Day) -> CellState
    var tap: (Day) -> Void

    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Self.letters[i])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { c in
                        if let d = week[c] {
                            cell(d)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Rows of seven, Monday first; blanks before the first day and after the last.
    private var weeks: [[Day?]] {
        var out: [[Day?]] = []
        var row = [Day?](repeating: nil, count: 7)
        for d in days {
            let c = (d.weekday + 6) % 7
            row[c] = d
            if c == 6 {
                out.append(row)
                row = [Day?](repeating: nil, count: 7)
            }
        }
        if row.contains(where: { $0 != nil }) { out.append(row) }
        return out
    }

    private func cell(_ d: Day) -> some View {
        let st = state(d)
        let off = st.kind == .missed
        let shape = RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
        return Button {
            tap(d)
        } label: {
            VStack(spacing: 2) {
                // The month on the first day shown and on every 1st.
                if d.day == 1 || d == days.first {
                    Text(d.date().formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 9, weight: .semibold))
                }
                Text("\(d.day)").font(.subheadline.weight(.semibold).monospacedDigit())
                if let h = st.hue {
                    Circle()
                        .fill(st.dotFilled ? Palette.hue(h) : .clear)
                        .overlay(Circle().strokeBorder(Palette.hue(h), lineWidth: 1.5))
                        .frame(width: 7, height: 7)
                } else if st.kind == .partial {
                    // Something was left out that day.
                    Capsule().fill(Palette.ink3).frame(width: 8, height: 2)
                }
            }
            .foregroundStyle(off ? Palette.ink3 : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(off ? Color.clear : Palette.ok.opacity(st.kind == .partial ? 0.12 : 0.22), in: shape)
            .overlay(shape.strokeBorder(off ? Palette.line2 : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
            .opacity(st.dim ? 0.35 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.long), \(off ? "missed" : st.kind == .partial ? "done, something left out" : "done")")
        .accessibilityHint("Double-tap to switch.")
    }
}
