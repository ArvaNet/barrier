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
    @State private var showFillIn = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    Picker("Routine", selection: $slot) {
                        Text("Evening").tag(Slot.pm)
                        Text("Morning").tag(Slot.am)
                        Text(model.state.plan.body.displayName).tag(Slot.body)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Group {
                    SlotEditorSections(slot: slot, editing: $editing, adding: $adding)
                    PausesSection(showPause: $showPause)
                    RoutineHistorySection()
                        .id("history")
                    if FillInSheet.available(model.state, today: model.today) {
                        Section {
                            Button { showFillIn = true } label: {
                                Label("Fill in the weeks before Tendwell…", systemImage: "calendar.badge.plus")
                            }
                        } footer: {
                            Text("Followed it before you set up Tendwell? Add those weeks so your timeline and report start when you did.")
                        }
                    }
                    Section {
                        Button { showTemplates = true } label: {
                            Label("Start over from a template…", systemImage: "rectangle.stack")
                        }
                    } footer: {
                        Text("Your history and photos stay. Only the routine is replaced.")
                    }
                }
                .rows()
            }
            .barrierList()
            .listSectionSpacing(.compact)
            .navigationTitle("Routine")
            .onAppear {
                // Screenshot hooks: `-screen routine-body`, `-screen routine-history`.
                if model.launch.screen == "routine-body" { slot = .body }
                // Sheets: the first active step's editor, the add sheet, the pause sheet.
                switch model.launch.screen {
                case "step-editor":
                    let actives = model.state.plan.pm.steps.first { model.product($0.productId)?.kind.isActive == true }
                    if editing == nil, let st = actives ?? model.state.plan.pm.steps.first { editing = StepTarget(slot: .pm, stepID: st.id) }
                case "add-product": if adding == nil { adding = .pm }
                case "pause": showPause = true
                default: break
                }
                if model.launch.screen == "routine-history" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("history", anchor: .top) }
                }
            }
            }
            .toolbar { EditButton() }
            .sheet(item: $editing) { t in
                StepEditorSheet(target: t).barrier(model)
            }
            .sheet(item: $adding) { s in
                AddProductSheet(slot: s).barrier(model).presentationDetents([.large])
            }
            .sheet(isPresented: $showPause) {
                PauseSheet().barrier(model).presentationDetents([.medium])
            }
            .sheet(isPresented: $showFillIn) {
                FillInSheet(start: FillInSheet.suggestedStart(model.state, today: model.today)).barrier(model)
            }
            .confirmationDialog("Start over from a template", isPresented: $showTemplates, titleVisibility: .visible) {
                ForEach(Presets.Template.allCases) { t in
                    Button(t.title) {
                        model.update { s in
                            let keepTimes = (s.plan.am.time, s.plan.pm.time)
                            let created = s.plan.createdAt
                            s = Presets.apply(t, to: s, today: model.today)
                            s.plan.am.time = keepTimes.0
                            s.plan.pm.time = keepTimes.1
                            s.plan.createdAt = created
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
            if slot == .body {
                BodyHeaderSection(sp: sp)
            } else {
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
        }

        if sp.enabled {
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
                    model.editPlan(slot) { s in
                        s.plan[slot].steps.remove(atOffsets: idx)
                        s.pruneOrphanProducts()
                    }
                }
                Button {
                    adding = slot
                } label: {
                    // The plus sits in the dot column, so the text lines up with the step names.
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.title3).frame(width: 10)
                        Text(sp.steps.isEmpty ? "Add a product" : "Add or reorder products")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Palette.accent)
                }
            } header: {
                Text("Steps, in order")
            } footer: {
                if sp.steps.isEmpty {
                    Text("Add what your dermatologist gave you, in the order you apply it.")
                } else if sp.steps.count > 1 {
                    Text("Tap a step for how often, the amount, or to start it slowly. To change the order, tap Add or reorder.")
                }
            }
            if !sp.steps.isEmpty && (slot == .pm || sp.length > 1 || !BuildUps.running(sp).isEmpty) {
                rotationSection(sp, products: products)
            }
        }
    }

    @ViewBuilder
    private func rotationSection(_ sp: SlotPlan, products: [String: Product]) -> some View {
        let today = model.today
        let unit = slot.word
        let nowWord = slot == .pm ? "tonight" : (slot == .am ? "this morning" : "today")
        let building = BuildUps.running(sp).compactMap { st in products[st.productId] }
        Section {
            if building.isEmpty {
                Stepper(value: Binding(
                    get: { sp.length },
                    set: { n in
                        model.editPlan(slot) { s in
                            s.plan[slot] = Engine.resize(s.plan[slot], to: n)
                        }
                    }
                ), in: 1...Engine.maxRotation) {
                    Text(sp.length == 1 ? "Same every \(unit)" : "Repeats every \(sp.length) \(unit)s")
                }
            }
            NextNights(slot: slot) { inst in
                if inst.day != today { confirmTonight = inst.pos }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
            Text("Next 7 \(unit)s")
        } footer: {
            if let p = building.first {
                Text("\(p.shortName) is building up, so the pattern changes as you move up. Tap a \(unit) to make it \(nowWord).")
            } else {
                Text(sp.length == 1 ? "Add \(unit)s for alternating routines, or tap a product to start it slowly." : "Tap a \(unit) to make it \(nowWord).")
            }
        }
        .confirmationDialog("Make \(nowWord) like this \(unit)?", isPresented: Binding(get: { confirmTonight != nil }, set: { if !$0 { confirmTonight = nil } }), titleVisibility: .visible) {
            Button("Yes, change \(nowWord)") {
                if let pos = confirmTonight {
                    model.update { s in
                        s.plan[slot].anchor = Anchor(day: today, pos: pos)
                        // Today's own log entry would advance it past `pos`.
                        if let e = s.entry(today, slot), e.status != .done { s.clearEntry(today, slot) }
                    }
                    model.show("\(nowWord.capitalized) is now \(model.instance(slot).label.lowercased()).")
                }
                confirmTonight = nil
            }
        } message: {
            Text("Use this to line Tendwell up with what you actually did. History stays as it is.")
        }
    }
}

/// The next seven nights as they'll actually run: build-ups, recovery nights and all.
struct NextNights: View {
    @Environment(AppModel.self) private var model
    var slot: Slot
    var onTap: (Instance) -> Void

    var body: some View {
        let today = model.today
        let nights = Engine.timeline(model.state, slot: slot, from: today, to: today.adding(6), today: today)
        // One line per kind of night, in the order they first appear.
        var seen: [String] = []
        var legend: [(label: String, hue: Hue, active: Bool)] = []
        for n in nights {
            let l = short(n)
            if !seen.contains(l) {
                seen.append(l)
                legend.append((l, n.hue, n.hasActives))
            }
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(nights) { n in
                    Button { onTap(n) } label: {
                        VStack(spacing: 6) {
                            Text(n.day == today ? (slot == .pm ? "Tonight" : "Today") : n.day.date().formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(n.day == today ? Palette.ink : Palette.ink3)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            dot(n)
                            Text("\(n.day.day)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(n.day == today ? Palette.fill : .clear, in: RoundedRectangle(cornerRadius: Metrics.compactRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n.day.relative(to: today)): \(n.label)")
                }
            }
            FlowLayout(spacing: 14) {
                ForEach(legend, id: \.label) { item in
                    HStack(spacing: 6) {
                        legendDot(item.hue, active: item.active)
                        Text(item.label).font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// "Adapalene", "Recovery", "Exfoliant + Tretinoin".
    private func short(_ n: Instance) -> String {
        if n.rest == .pause { return "Basics only" }
        let actives = n.steps.filter(\.active).map(\.product.shortName)
        if actives.isEmpty { return slot == .pm ? "Recovery" : (slot == .am ? "Basics" : n.label) }
        return actives.joined(separator: " + ")
    }

    private func dot(_ n: Instance) -> some View {
        legendDot(n.hue, active: n.hasActives, size: 14)
    }

    private func legendDot(_ hue: Hue, active: Bool, size: CGFloat = 9) -> some View {
        ZStack {
            if active {
                Circle().fill(Palette.hue(hue))
            } else {
                Circle().strokeBorder(Palette.hue(hue), lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

struct StepRow: View {
    var step: Step
    var product: Product
    var sp: SlotPlan
    var slot: Slot
    /// A drag handle instead of the chevron, where rows reorder by holding and dragging.
    var handle = false

    var body: some View {
        HStack(spacing: 12) {
            // Treatment steps carry their hue; basics leave the column empty (not a checkbox).
            Group {
                if let hue = product.kind.hue { HueDot(hue: hue, size: 10) } else { Color.clear }
            }
            .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                Text(detail).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let w = step.waitMin, w > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "hourglass")
                    Text("\(w) min")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink3)
            }
            if handle {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink3)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var detail: String {
        var parts = [Engine.describe(step, in: sp, slot: slot)]
        if let b = step.buildUp, !b.done {
            parts[0] += ", building up to \(PlanHistory.lowered(Engine.everyPhrase(b.goal, word: slot.word)))"
        }
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
                    // A Label, so the text lines up with "Pause the plan…" below.
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(p))
                            Text(p.from == p.to ? p.from.short : "\(p.from.short) – \(p.to.short)").font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: p.reason == .travel ? "airplane" : "pause.circle").foregroundStyle(Palette.hueInk(.mist))
                    }
                    Spacer()
                    Button(p.from <= today ? "End" : "Remove") { model.endPause(p) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(p.from <= today ? Palette.ink : Palette.danger)
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

    /// "Traveling", or "Actives break: Subcision" for a procedure's break.
    private func label(_ p: Pause) -> String {
        guard let id = p.procedureID, let proc = model.state.procedures.first(where: { $0.id == id }) else { return p.reason.label }
        let scope = p.area == .body ? " (\(model.bodyAreaName))" : ""
        return "Actives break: \(proc.name)\(scope)"
    }
}

// MARK: - History

/// What changed in the routine and when, newest first. It goes in the report too.
struct RoutineHistorySection: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    var body: some View {
        let changes = Array(PlanHistory.changes(model.state).reversed())
        let shown = showAll ? changes : Array(changes.prefix(4))
        Section {
            if changes.isEmpty {
                Text(startLine).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(shown) { c in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(c.day.short).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(c.lines.enumerated()), id: \.offset) { _, line in Text(line).font(.subheadline) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if changes.count > shown.count {
                Button("Show all \(changes.count)") { showAll = true }
            }
        } header: {
            Text("History")
        } footer: {
            Text("Tendwell notes what changed and when (one entry per day), so your dermatologist can see it in the report.")
        }
    }

    private var startLine: String {
        guard let first = model.state.history.first else { return "Changes to your routine will show here." }
        return "Changes noted from \(first.day.short). None since."
    }
}

// MARK: - Body routine header

/// Name, cue ("After shower") and time for the body routine.
struct BodyHeaderSection: View {
    @Environment(AppModel.self) private var model
    var sp: SlotPlan

    var body: some View {
        Section {
            Toggle("\(sp.displayName) routine", isOn: Binding(
                get: { sp.enabled },
                set: { v in model.update { $0.plan.body.enabled = v } }
            ))
            if sp.enabled {
                HStack {
                    Text("Name")
                    TextField("Back", text: Binding(
                        get: { sp.name ?? "" },
                        set: { v in model.update { $0.plan.body.name = v } }
                    ))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.sentences)
                    // It's editable: say so.
                    Image(systemName: "pencil").font(.footnote).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                }
                Picker("When", selection: Binding(
                    get: { sp.cue ?? "" },
                    set: { v in model.update { $0.plan.body.cue = v.isEmpty ? nil : v } }
                )) {
                    Text("At a set time").tag("")
                    ForEach(Presets.bodyCues, id: \.self) { Text($0).tag($0) }
                }
                DatePicker((sp.cue ?? "").isEmpty ? "Remind me at" : "Usually around", selection: Binding(
                    get: { sp.time.date },
                    set: { d in model.update { $0.plan.body.time = ClockTime(date: d) } }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Body routine")
        } footer: {
            Text(sp.enabled
                 ? "Its own reminder and log, and it never changes your face routine. The reminder reads “\(sp.cue ?? sp.displayName)\(sp.cue == nil ? "" : ": " + sp.displayName.lowercased())”."
                 : "For a treatment on your back, chest or body, like a lotion after the shower.")
        }
    }
}
