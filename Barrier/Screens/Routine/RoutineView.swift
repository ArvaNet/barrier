import BarrierCore
import SwiftUI

struct StepTarget: Identifiable, Hashable {
    var slot: Slot
    var stepID: String
    var id: String { "\(slot.rawValue)-\(stepID)" }
}

struct RoutineView: View {
    @Environment(AppModel.self) private var model
    @State private var slot: Slot = .pm
    @State private var editing: StepTarget?
    @State private var adding: Slot?
    @State private var showTemplates = false
    @State private var showPause = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Routine", selection: $slot) {
                        Text("Evening").tag(Slot.pm)
                        Text("Morning").tag(Slot.am)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                SlotEditorSections(slot: slot, editing: $editing, adding: $adding)
                PausesSection(showPause: $showPause)
                Section {
                    Button("Start over from a template…") { showTemplates = true }
                        .foregroundStyle(Palette.accent)
                } footer: {
                    Text("Your history and photos stay. Only the routine is replaced.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Routine")
            .toolbar { EditButton() }
            .sheet(item: $editing) { t in
                StepEditorSheet(target: t).environment(model)
            }
            .sheet(item: $adding) { s in
                AddProductSheet(slot: s).environment(model).presentationDetents([.large])
            }
            .sheet(isPresented: $showPause) {
                PauseSheet().environment(model).presentationDetents([.medium])
            }
            .confirmationDialog("Start over from a template", isPresented: $showTemplates, titleVisibility: .visible) {
                ForEach(Presets.Template.allCases) { t in
                    Button(t.title) {
                        model.update { s in
                            let keepTimes = (s.plan.am.time, s.plan.pm.time)
                            s = Presets.apply(t, to: s, today: model.today)
                            s.plan.am.time = keepTimes.0
                            s.plan.pm.time = keepTimes.1
                        }
                        model.show("Routine replaced. History kept.")
                    }
                }
            } message: {
                Text("This replaces your current morning and evening routines.")
            }
        }
    }
}

/// Reminder time, rotation, steps and ease-in for one slot. Also used in onboarding.
struct SlotEditorSections: View {
    @Environment(AppModel.self) private var model
    var slot: Slot
    @Binding var editing: StepTarget?
    @Binding var adding: Slot?
    var showTime = true
    @State private var confirmTonight: Int?

    var body: some View {
        let sp = model.state.plan[slot]
        let products = model.products
        if showTime {
            Section {
                Toggle(slot == .pm ? "Evening routine" : "Morning routine", isOn: Binding(
                    get: { sp.enabled },
                    set: { v in model.update { $0.plan[slot].enabled = v } }
                ))
                if sp.enabled {
                    DatePicker("Remind me at", selection: Binding(
                        get: { sp.time.date },
                        set: { d in model.update { $0.plan[slot].time = ClockTime(date: d) } }
                    ), displayedComponents: .hourAndMinute)
                }
            }
        }

        if sp.enabled {
            if slot == .pm || sp.length > 1 {
                rotationSection(sp, products: products)
            }
            Section {
                ForEach(sp.steps) { step in
                    if let p = products[step.productId] {
                        Button {
                            editing = StepTarget(slot: slot, stepID: step.id)
                        } label: {
                            StepRow(step: step, product: p, sp: sp, slot: slot)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in
                    model.update { $0.plan[slot].steps.move(fromOffsets: from, toOffset: to) }
                }
                .onDelete { idx in
                    model.update { s in
                        s.plan[slot].steps.remove(atOffsets: idx)
                        s.pruneOrphanProducts()
                    }
                }
                Button {
                    adding = slot
                } label: {
                    Label("Add a product", systemImage: "plus.circle.fill")
                        .foregroundStyle(Palette.accent)
                }
            } header: {
                Text("Steps, in order")
            } footer: {
                if sp.steps.isEmpty {
                    Text("Add what your dermatologist gave you, in the order you apply it.")
                }
            }
            if slot == .pm && sp.steps.contains(where: { products[$0.productId]?.kind.isActive == true }) {
                EaseInSection(slot: slot)
            }
        }
    }

    @ViewBuilder
    private func rotationSection(_ sp: SlotPlan, products: [String: Product]) -> some View {
        let today = model.today
        let tonight = model.instance(slot)
        let nodes = Engine.rotationNodes(model.state, slot: slot, on: today)
        Section {
            Stepper(value: Binding(
                get: { sp.length },
                set: { n in
                    model.update { s in
                        s.plan[slot] = Engine.resize(s.plan[slot], to: n)
                        s.rebase(slot, today: today, keeping: tonight)
                    }
                }
            ), in: 1...8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sp.length == 1 ? "Same every night" : "Repeats every \(sp.length) nights")
                    Text(sp.length == 1 ? "Add nights for alternating routines." : "Tap a night to make it tonight.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if nodes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(nodes, id: \.pos) { n in
                            Button {
                                if n.pos != tonight.pos { confirmTonight = n.pos }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 5) {
                                        HueDot(hue: n.hue, size: 9)
                                        Text("Night \(n.pos + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    }
                                    Text(n.label.replacingOccurrences(of: " night", with: ""))
                                        .font(.footnote.weight(.medium))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if n.pos == tonight.pos {
                                        Text("Tonight").font(.caption2.weight(.bold)).foregroundStyle(Palette.accent)
                                    }
                                }
                                .frame(width: 86, alignment: .leading)
                                .padding(10)
                                .background(n.pos == tonight.pos ? Palette.accentSoft : Palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        } header: {
            Text("Rotation")
        }
        .confirmationDialog("Make tonight night \((confirmTonight ?? 0) + 1)?", isPresented: Binding(get: { confirmTonight != nil }, set: { if !$0 { confirmTonight = nil } }), titleVisibility: .visible) {
            Button("Yes, tonight is night \((confirmTonight ?? 0) + 1)") {
                if let pos = confirmTonight {
                    model.update { s in
                        s.plan[slot].anchor = Anchor(day: today, pos: pos)
                        // Today's own log entry would advance it past `pos`.
                        if let e = s.entry(today, slot), e.status != .done { s.clearEntry(today, slot) }
                    }
                    model.show("Tonight is now night \(pos + 1).")
                }
                confirmTonight = nil
            }
        } message: {
            Text("Use this to line Barrier up with what you actually did. History stays as it is.")
        }
    }
}

struct StepRow: View {
    var step: Step
    var product: Product
    var sp: SlotPlan
    var slot: Slot

    var body: some View {
        HStack(spacing: 12) {
            if let hue = product.kind.hue {
                HueDot(hue: hue, size: 10)
            } else {
                Circle().strokeBorder(Palette.line2, lineWidth: 1.2).frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                Text(detail).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let w = step.waitMin, w > 0 {
                Label("\(w)m", systemImage: "hourglass").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3.opacity(0.6))
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts = [Engine.describe(step, in: sp, slot: slot)]
        if let a = step.amount, !a.isEmpty { parts.append(a) }
        if let u = product.until { parts.append("until \(u.short)") }
        return parts.joined(separator: " · ")
    }
}

extension ProductKind {
    /// The hue a product's nights wear (actives only).
    var hue: Hue? {
        switch self {
        case .retinoid: return .clay
        case .exfoliant: return .gold
        case .treatment: return .rose
        default: return nil
        }
    }
}

// MARK: - Ease in

struct EaseInSection: View {
    @Environment(AppModel.self) private var model
    var slot: Slot

    var body: some View {
        let sp = model.state.plan[slot]
        let today = model.today
        Section {
            Toggle("Ease in gradually", isOn: Binding(
                get: { sp.easeIn != nil },
                set: { on in
                    let tonight = model.instance(slot)
                    model.update { s in
                        s.plan[slot].easeIn = on ? EaseIn(start: today, phases: Presets.easeInPhases) : nil
                        s.rebase(slot, today: today, keeping: tonight)
                    }
                }
            ))
            if let ease = sp.easeIn {
                DatePicker("Started", selection: Binding(
                    get: { ease.start.date() },
                    set: { d in model.update { $0.plan[slot].easeIn?.start = Day(date: d) } }
                ), displayedComponents: .date)
                ForEach(Array(ease.phases.enumerated()), id: \.offset) { i, phase in
                    phaseRow(i, phase, ease: ease, length: sp.length)
                }
                HStack {
                    Button("Add a step") {
                        model.update { s in
                            let last = s.plan[slot].easeIn?.phases.last?.extraRest ?? 1
                            s.plan[slot].easeIn?.phases.append(EaseInPhase(days: 14, extraRest: max(0, last - 1)))
                        }
                    }
                    Spacer()
                    if ease.phases.count > 1 {
                        Button("Remove last", role: .destructive) {
                            model.update { _ = $0.plan[slot].easeIn?.phases.popLast() }
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderless)
                let end = ease.start.adding(ease.totalDays)
                Text(end > today ? "Full routine from \(end.short)." : "Ease-in finished on \(end.short). You’re on the full routine.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Easing in")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Guidance.easeIn.body)
                SourcesView(sources: Guidance.easeIn.sources)
            }
        }
    }

    private func phaseRow(_ i: Int, _ phase: EaseInPhase, ease: EaseIn, length: Int) -> some View {
        let startDay = ease.phases.prefix(i).reduce(0) { $0 + $1.days }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Days \(startDay + 1)–\(startDay + phase.days)").font(.subheadline.weight(.semibold))
            Stepper(value: Binding(
                get: { phase.days },
                set: { v in model.update { $0.plan[slot].easeIn?.phases[i].days = v } }
            ), in: 7...56, step: 7) {
                Text("\(phase.days / 7) week\(phase.days == 7 ? "" : "s")").font(.subheadline)
            }
            Stepper(value: Binding(
                get: { phase.extraRest },
                set: { v in
                    let tonight = model.instance(slot)
                    model.update { s in
                        s.plan[slot].easeIn?.phases[i].extraRest = v
                        s.rebase(slot, today: model.today, keeping: tonight)
                    }
                }
            ), in: 0...6) {
                Text(frequencyText(extra: phase.extraRest, length: length)).font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private func frequencyText(extra: Int, length: Int) -> String {
        if length == 1 {
            switch extra {
            case 0: return "Actives every night"
            case 1: return "Actives every other night"
            default: return "Actives every \(extra + 1)\(extra + 1 == 3 ? "rd" : "th") night"
            }
        }
        return extra == 0 ? "Normal rotation" : "+\(extra) recovery night\(extra == 1 ? "" : "s") per cycle"
    }
}

// MARK: - Pauses

struct PausesSection: View {
    @Environment(AppModel.self) private var model
    @Binding var showPause: Bool

    var body: some View {
        let today = model.today
        let relevant = model.state.pauses.filter { $0.to >= today }.sorted { $0.from < $1.from }
        Section {
            ForEach(relevant) { p in
                HStack {
                    Image(systemName: p.reason == .travel ? "airplane" : "pause.circle").foregroundStyle(Palette.hueInk(.mist))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.reason.label)
                        Text(p.from == p.to ? p.from.short : "\(p.from.short) – \(p.to.short)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(p.from <= today ? "End" : "Remove") {
                        model.update { $0.endPause(p.id, today: today) }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.accent)
                }
            }
            Button {
                showPause = true
            } label: {
                Label("Pause the plan…", systemImage: "pause.circle")
            }
        } header: {
            Text("Breaks")
        } footer: {
            Text("Traveling, a procedure, or skin that needs a rest. Reminders switch to the basics and the rotation waits.")
        }
    }
}
