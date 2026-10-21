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
                    if let c = model.state.checkIn(on: day, area: area) {
                        Section(area == .face ? "Skin" : "Skin · \(model.state.plan.body.displayName)") {
                            Text(c.feel.map(\.label).joined(separator: ", "))
                            if let n = c.note { Text(n).foregroundStyle(.secondary) }
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
