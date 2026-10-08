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
                Section {
                    option("Skip tonight", detail: inst.hasActives ? "Tomorrow picks up \(inst.label.lowercased()) where you left off." : "Rest nights still count.", symbol: "moon.zzz") {
                        model.markSkipped(inst)
                        dismiss()
                    }
                    if inst.slot == .pm && inst.hasActives && inst.rest == nil {
                        option("Skin’s irritated: recovery night", detail: "Drops the actives tonight. Your rotation waits.", symbol: "leaf") {
                            model.setRecovery(inst.day, inst.slot, on: true)
                            dismiss()
                        }
                    }
                    option("Pause the plan…", detail: "Traveling, a procedure, or a break. Basics only until you’re back.", symbol: "pause.circle") {
                        showPause = true
                    }
                }
                if let derm = model.state.plan.ifIrritated, !derm.isEmpty {
                    Section("Your dermatologist said") {
                        Text(derm).font(.subheadline)
                    }
                }
            }
            .navigationTitle(inst.slot == .pm ? "Not tonight?" : "Not this morning?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showPause) {
                PauseSheet { dismiss() }.barrier(model).presentationDetents([.medium])
            }
        }
    }

    private func option(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 28)
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
                Picker("Why", selection: $reason) {
                    ForEach(PauseReason.allCases) { Text($0.label).tag($0) }
                }
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("Until", selection: $to, in: from..., displayedComponents: .date)
                Section {
                    Text("Reminders switch to the basics (cleanse, moisturize, sunscreen). When the pause ends, your rotation continues exactly where it stopped.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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

    var body: some View {
        NavigationStack {
            List {
                ForEach([Slot.pm, .am], id: \.self) { slot in
                    let sp = model.state.plan[slot]
                    if sp.enabled && !sp.steps.isEmpty && day >= model.state.plan.createdAt || model.state.entry(day, slot) != nil {
                        section(slot)
                    }
                }
                if let c = model.state.checkIn(on: day) {
                    Section("Skin") {
                        Text(c.feel.map(\.label).joined(separator: ", "))
                        if let n = c.note { Text(n).foregroundStyle(.secondary) }
                    }
                }
                if model.state.photos.contains(where: { $0.day == day }) {
                    Section {
                        Label("Progress photo taken", systemImage: "camera")
                    }
                }
            }
            .navigationTitle(day.long)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func section(_ slot: Slot) -> some View {
        let inst = model.instance(slot, on: day)
        Section {
            HStack(spacing: 10) {
                HueDot(hue: inst.hue, size: 12, hollow: !inst.isDone)
                Text(inst.label.isEmpty ? (slot == .pm ? "Evening" : "Morning") : inst.label).font(.headline)
                Spacer()
                Text(statusText(inst)).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(inst.steps, id: \.step.id) { s in
                HStack {
                    Text(s.product.name)
                    Spacer()
                    if let a = s.step.amount { Text(a).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            if day <= model.today && inst.status != .off {
                if inst.isResolved {
                    Button("Clear what was logged", role: .destructive) { model.undoEntry(inst) }
                } else {
                    Button("Mark done") { model.markDone(inst, quiet: true) }
                    Button("Mark skipped") { model.markSkipped(inst) }
                }
            }
        } header: {
            Text(slot == .pm ? "Evening" : "Morning")
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
