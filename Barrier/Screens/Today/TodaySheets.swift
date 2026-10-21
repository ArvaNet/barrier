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
                        option(inst.slot == .body ? "Skin’s irritated: gentle day" : "Skin’s irritated: recovery night",
                               detail: inst.slot == .body ? "Leaves out the treatment today. Your face routine isn’t affected." : "Drops the actives tonight. Your rotation waits.",
                               symbol: "leaf") {
                            model.setRecovery(inst.day, inst.slot, on: true)
                            dismiss()
                        }
                    }
                    option("Pause the plan…", detail: inst.slot == .body
                           ? "Pauses your face routines too. Basics only until you’re back."
                           : "Traveling, a procedure, or a break. Basics only until you’re back.", symbol: "pause.circle") {
                        showPause = true
                    }
                }
                if inst.slot != .body, let derm = model.state.plan.ifIrritated, !derm.isEmpty {
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
        case .body: return "Skip today"
        }
    }

    private var skipDetail: String {
        if inst.hasActives && inst.cycleLen > 1 {
            return inst.slot == .body ? "Next time picks up where you left off." : "Next time picks up \(inst.label.lowercased()) where you left off."
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
                ForEach([Slot.pm, .am, .body], id: \.self) { slot in
                    let sp = model.state.plan[slot]
                    // The body routine starts later than the plan: no empty sections before it.
                    let started = day >= model.state.plan.createdAt && (slot != .body || day >= sp.anchor.day)
                    if (sp.enabled && !sp.steps.isEmpty && started) || model.state.entry(day, slot) != nil {
                        section(slot)
                    }
                }
                ForEach(Area.allCases) { area in
                    let c = model.state.checkIn(on: day, area: area)
                    // Any day up to today can say how the skin was (missed days, the weeks before Barrier).
                    let canLog = day <= model.today && (area == .face || model.state.plan.body.enabled)
                    if c != nil || canLog {
                        Section(area == .face ? "Skin" : "Skin · \(model.state.plan.body.displayName)") {
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
        let selected = Set(existing?.feel ?? [])
        FlowLayout(spacing: 8) {
            ForEach(Feeling.allCases) { f in
                Chip(title: f.label, selected: selected.contains(f), hue: nil) {
                    var set = selected
                    if set.contains(f) { set.remove(f) } else { set.insert(f) }
                    // Calm and a symptom don't go together.
                    if f == .calm && set.contains(.calm) { set = [.calm] } else if f != .calm { set.remove(.calm) }
                    let ordered = Feeling.allCases.filter { set.contains($0) }
                    model.update { $0.checkIn(day, feel: ordered, note: existing?.note, area: area) }
                    Haptics.tap(model.state.settings.haptics)
                }
            }
        }
        .padding(.vertical, 4)
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
    @State private var slot: Slot = .pm

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
        NavigationStack {
            List {
                Group {
                    Section {
                        DatePicker("Following it since", selection: $start, in: earliest.date()...last.date(), displayedComponents: .date)
                    } footer: {
                        Text("Every day from then until \(last.short) counts as done. Tap the days you missed.")
                    }
                    Section {
                        if slots.count > 1 {
                            Picker("Routine", selection: $slot) {
                                ForEach(slots, id: \.self) { Text($0.name(s.plan)).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        FillInGrid(days: days, missed: Binding(
                            get: { missed[shown] ?? [] },
                            set: { missed[shown] = $0 }
                        ))
                    } header: {
                        Text("\(shown.name(s.plan)) · \(days.count - off.count) of \(days.count) done")
                    } footer: {
                        Text("Saved as filled in afterwards, and your report says so. Change any day later from the calendar in Progress.")
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
        }
    }

    private func save() {
        let from = Day(date: start)
        let n = model.state.fillInDays(since: from).count
        let before = model.state
        let m = model
        m.update { $0.fillIn(since: from, missed: missed, today: m.today) }
        m.show("Filled in \(n) day\(n == 1 ? "" : "s") from \(from.short).") {
            m.update { $0 = before }
        }
        Haptics.success(model.state.settings.haptics)
        dismiss()
    }
}

/// The days as a calendar, Monday first: done in sage, a tap marks one missed.
private struct FillInGrid: View {
    var days: [Day]
    @Binding var missed: Set<Day>

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
                            Color.clear.frame(maxWidth: .infinity, minHeight: 44)
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
        let off = missed.contains(d)
        let shape = RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
        return Button {
            if off { missed.remove(d) } else { missed.insert(d) }
        } label: {
            VStack(spacing: 0) {
                // The month on the first day shown and on every 1st.
                if d.day == 1 || d == days.first {
                    Text(d.date().formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 9, weight: .semibold))
                }
                Text("\(d.day)").font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(off ? Palette.ink3 : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(off ? Color.clear : Palette.ok.opacity(0.22), in: shape)
            .overlay(shape.strokeBorder(off ? Palette.line2 : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.long), \(off ? "missed" : "done")")
        .accessibilityHint("Double-tap to switch.")
    }
}
