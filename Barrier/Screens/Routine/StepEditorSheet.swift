import BarrierCore
import SwiftUI

/// Edit one step and its product: name, kind, amount, wait, schedule, dates.
struct StepEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var target: StepTarget

    @State private var product = Product(name: "", kind: .other)
    @State private var step = Step(productId: "")
    @State private var freq: Freq = .every(1)
    @State private var nights: Set<Int> = []
    @State private var weekdays: Set<Int> = []
    @State private var hasFrom = false
    @State private var from = Date()
    @State private var hasUntil = false
    @State private var until = Date().addingTimeInterval(84 * 86400)
    @State private var loaded = false
    @State private var confirmRemove = false
    @State private var cantFit = false
    /// The schedule as it was opened, so saving a name or note never moves the step.
    @State private var originalFreq: Freq = .every(1)
    @State private var originalNights: Set<Int> = []
    @State private var originalWeekdays: Set<Int> = []
    /// Starting slowly: on, the stages, and the build-up as it was opened.
    @State private var buildOn = false
    @State private var stages: [BuildStage] = Presets.buildUpStages
    @State private var originalBuild: BuildUp?
    /// When the current stage began ("I've been doing this since Oct 8").
    @State private var stageSince = Date()

    enum Freq: Hashable {
        case every(Int)
        case nights
        case weekdays
    }

    var body: some View {
        let sp = model.state.plan[target.slot]
        NavigationStack {
            Form {
                Group {
                Section("Product") {
                    TextField("Name", text: $product.name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $product.kind) {
                        ForEach(ProductKind.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    TextField("Exactly what they told you", text: Binding(get: { product.note ?? "" }, set: { product.note = $0 }), axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Your dermatologist’s instructions")
                }
                Section {
                    TextField("Amount, e.g. pea-size", text: Binding(get: { step.amount ?? "" }, set: { step.amount = $0 }))
                    TextField("How, e.g. on dry skin", text: Binding(get: { step.how ?? "" }, set: { step.how = $0 }), axis: .vertical)
                    Stepper(value: Binding(get: { step.waitMin ?? 0 }, set: { step.waitMin = $0 == 0 ? nil : $0 }), in: 0...60, step: 5) {
                        Text((step.waitMin ?? 0) == 0 ? "No wait after" : "Wait \(step.waitMin!) min after")
                    }
                } header: {
                    Text("How to use it")
                } footer: {
                    Text("A wait shows a timer in the routine, on your Lock Screen, and pings you when it’s over.")
                }
                Section {
                    Picker(buildOn ? "Building up to" : "How often", selection: $freq) {
                        Text("Every \(target.slot.word)").tag(Freq.every(1))
                        Text("Every other \(target.slot.word)").tag(Freq.every(2))
                        Text("Every 3rd \(target.slot.word)").tag(Freq.every(3))
                        Text("Every 4th \(target.slot.word)").tag(Freq.every(4))
                        if sp.length > 1 { Text("Pick \(target.slot.word)s in the rotation").tag(Freq.nights) }
                        Text("Specific weekdays").tag(Freq.weekdays)
                    }
                    if freq == .nights {
                        FlowLayout(spacing: 8) {
                            ForEach(Engine.rotationNodes(model.state, slot: target.slot, on: model.today).filter { !$0.rest }, id: \.pos) { n in
                                Chip(title: "\(target.slot.word.capitalized) \(n.pos + 1)", selected: nights.contains(n.pos), hue: n.hue) {
                                    if nights.contains(n.pos) { nights.remove(n.pos) } else { nights.insert(n.pos) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if freq == .weekdays {
                        FlowLayout(spacing: 8) {
                            ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { d in
                                Chip(title: Calendar.current.shortWeekdaySymbols[d], selected: weekdays.contains(d), hue: nil) {
                                    if weekdays.contains(d) { weekdays.remove(d) } else { weekdays.insert(d) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("When")
                } footer: {
                    if case .every(let n) = freq, n > 1 {
                        Text("Tendwell counts \(target.slot.word)s you actually do. Miss one and the next \(target.slot.word) picks up where you left off.")
                    }
                }
                if canBuildUp {
                    BuildUpSection(slot: target.slot, on: $buildOn, stages: $stages, existing: runningBuild, goal: goalEvery,
                                   since: $stageSince, moveUpNow: moveUpNow)
                }
                Section {
                    Toggle("Started on", isOn: $hasFrom)
                    if hasFrom { DatePicker("Start", selection: $from, displayedComponents: .date) }
                    Toggle("Course ends", isOn: $hasUntil)
                    if hasUntil { DatePicker("Last day", selection: $until, displayedComponents: .date) }
                } header: {
                    Text("Dates")
                } footer: {
                    Text("A start date in the future holds the step until then. A last day is for courses, like a 12-week prescription.")
                }
                Section {
                    Button("Remove from \(target.slot.name(model.state.plan).lowercased())", role: .destructive) { confirmRemove = true }
                }
                }
                .rows()
            }
            .barrierList()
            .navigationTitle(product.name.isEmpty ? "Step" : product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(product.name.trimmingCharacters(in: .whitespaces).isEmpty).tint(Palette.accent)
                }
            }
            .confirmationDialog("Remove \(product.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.editPlan(target.slot) { s in
                        s.plan[target.slot].steps.removeAll { $0.id == target.stepID }
                        s.pruneOrphanProducts()
                    }
                    dismiss()
                }
            }
            .alert("That pattern doesn’t fit", isPresented: $cantFit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("With your other steps, the rotation would need more than \(Engine.maxRotation) nights. Pick the exact nights or weekdays instead.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let sp = model.state.plan[target.slot]
        guard let s = sp.steps.first(where: { $0.id == target.stepID }), let p = model.product(s.productId) else { return }
        step = s
        product = p
        if let f = p.from { hasFrom = true; from = f.date() }
        if let u = p.until { hasUntil = true; until = u.date() }
        switch s.on {
        case .all: freq = .every(1)
        case .weekdays(let d):
            freq = .weekdays
            weekdays = Set(d)
        case .nights(let n):
            nights = Set(n)
            if let gap = Engine.every(of: s, length: sp.length), gap <= 4 { freq = .every(gap) } else { freq = .nights }
        }
        if let b = s.buildUp, !b.done {
            buildOn = true
            stages = b.stages
            originalBuild = b
            stageSince = b.stageStart(b.stage).date()
            // The picker shows the goal; the step's own schedule is the current stage.
            freq = .every(b.goal)
        } else if p.kind == .retinoid && !(s.buildUp?.done ?? false) {
            stages = Presets.buildUpStages
        }
        originalFreq = freq
        originalNights = nights
        originalWeekdays = weekdays
    }

    /// Starting slowly fits an "every Nth" goal, for treatments (or one already building up).
    private var canBuildUp: Bool {
        guard case .every = freq else { return false }
        return product.kind.isActive || runningBuild != nil
    }

    private var goalEvery: Int {
        if case .every(let n) = freq { return n }
        return 1
    }

    private var runningBuild: BuildUp? { originalBuild }

    private func moveUpNow() {
        var ok = true
        model.update { ok = $0.moveUp(target.slot, stepID: target.stepID, today: model.today) }
        if ok {
            Haptics.success(model.state.settings.haptics)
            if let b = model.state.plan[target.slot].steps.first(where: { $0.id == target.stepID })?.buildUp {
                model.show("\(product.shortName): \(PlanHistory.lowered(Engine.everyPhrase(b.every, word: target.slot.word))) from now.")
            }
        } else {
            model.show("That doesn’t fit your rotation.")
        }
        dismiss()
    }

    private func save() {
        let slot = target.slot
        var p = product
        p.name = p.name.trimmingCharacters(in: .whitespaces)
        p.note = p.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.from = hasFrom ? Day(date: from) : nil
        p.until = hasUntil ? Day(date: until) : nil
        var st = step
        st.amount = st.amount?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        st.how = st.how?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let scheduleChanged = freq != originalFreq
            || (freq == .nights && nights != originalNights)
            || (freq == .weekdays && weekdays != originalWeekdays)
        // Check the pattern fits before changing anything.
        if scheduleChanged, case .every(let n) = freq, n > 1 {
            var probe = model.state.plan[slot]
            if let i = probe.steps.firstIndex(where: { $0.id == st.id }) { probe.steps[i] = st }
            let products = model.products.merging([p.id: p]) { _, new in new }
            if Engine.setEvery(probe, stepID: st.id, n: n, products: products) == nil {
                cantFit = true
                return
            }
        }
        let building = buildOn && canBuildUp && !stages.isEmpty
        if building || originalBuild != nil {
            saveBuildUp(product: p, step: st, building: building, scheduleChanged: scheduleChanged)
            return
        }
        // Any change here (type, dates, schedule) can change what's due, so keep tonight fixed.
        model.editPlan(slot) { s in
            s.upsertProduct(p)
            guard let i = s.plan[slot].steps.firstIndex(where: { $0.id == st.id }) else { return }
            s.plan[slot].steps[i] = st
            guard scheduleChanged else { return }
            let products = Dictionary(s.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            switch freq {
            case .every(let n):
                if let plan = Engine.setEvery(s.plan[slot], stepID: st.id, n: n, products: products) { s.plan[slot] = plan }
            case .nights:
                s.plan[slot].steps[i].on = .nights(nights.sorted())
            case .weekdays:
                s.plan[slot].steps[i].on = .weekdays(weekdays.sorted())
            }
        }
        dismiss()
    }
}

extension StepEditorSheet {
    /// Save when starting slowly, or when a build-up was running: the step's schedule is
    /// the current stage, the picker is the goal.
    fileprivate func saveBuildUp(product p: Product, step st: Step, building: Bool, scheduleChanged: Bool) {
        let slot = target.slot
        let today = model.today
        let goal = goalEvery
        let wanted = stages.filter { $0.every > goal }
        var failed = false
        model.update { s in
            s.upsertProduct(p)
            guard let i = s.plan[slot].steps.firstIndex(where: { $0.id == st.id }) else { return }
            var fields = st
            fields.on = s.plan[slot].steps[i].on
            fields.buildUp = s.plan[slot].steps[i].buildUp
            s.plan[slot].steps[i] = fields
            let old = fields.buildUp.flatMap { $0.done ? nil : $0 }
            switch (old, building && !wanted.isEmpty) {
            case (nil, true):
                // Starting now: the goal first, then the first stage.
                if Engine.every(of: s.plan[slot].steps[i], length: s.plan[slot].length) != goal {
                    s.lineUp(slot, stepID: st.id, every: goal, wait: 0, today: today)
                }
                // Started earlier ("since Oct 8")? The first stage counts from then.
                let start = Day(date: stageSince) < today ? Day(date: stageSince) : (p.from ?? today)
                failed = !s.startBuildUp(slot, stepID: st.id, stages: wanted, start: start, today: today)
            case (var b?, true):
                // Editing a running build-up: stages already passed stay as they were.
                let before = b.every
                let passed = Array(b.stages.prefix(b.moves.count))
                b.stages = passed + wanted.dropFirst(min(passed.count, wanted.count))
                if b.stages.count < passed.count { b.stages = passed }
                b.goal = goal
                if b.moves.count > b.stages.count { b.moves = Array(b.moves.prefix(b.stages.count)) }
                // The current stage's start, as set: never before the stage before it, never after today.
                let since = min(Day(date: stageSince), today)
                if b.moves.isEmpty {
                    b.start = since
                } else {
                    let floor = b.moves.count >= 2 ? b.moves[b.moves.count - 2] : b.start
                    b.moves[b.moves.count - 1] = max(floor, since)
                }
                if b.every != before {
                    let wait = s.waitFor(slot, stepID: st.id, every: b.every, today: today)
                    failed = !s.lineUp(slot, stepID: st.id, every: b.every, wait: wait, today: today)
                }
                if !failed, let j = s.plan[slot].steps.firstIndex(where: { $0.id == st.id }) { s.plan[slot].steps[j].buildUp = b }
            case (_?, false):
                // Turned off: straight to the goal from tonight.
                s.plan[slot].steps[i].buildUp?.goal = goal
                s.endBuildUp(slot, stepID: st.id, today: today)
            case (nil, false):
                if scheduleChanged {
                    let wait = s.waitFor(slot, stepID: st.id, every: goal, today: today)
                    failed = !s.lineUp(slot, stepID: st.id, every: goal, wait: wait, today: today)
                }
            }
        }
        if failed {
            cantFit = true
            return
        }
        dismiss()
    }
}

/// "Start slowly": stages before the goal, each a frequency and a few weeks.
/// Menus, not steppers, so each stage reads as one clean line.
struct BuildUpSection: View {
    var slot: Slot
    @Binding var on: Bool
    @Binding var stages: [BuildStage]
    var existing: BuildUp?
    var goal: Int
    @Binding var since: Date
    var moveUpNow: () -> Void

    var body: some View {
        let word = slot.word
        let passed = existing?.moves.count ?? 0
        Section {
            Toggle(isOn: $on.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start slowly")
                    Text("A few times a week first, then more often.")
                        .font(.footnote).foregroundStyle(Palette.ink3)
                }
            }
            if on {
                DatePicker(existing == nil ? "Doing this since" : "On this stage since",
                           selection: $since, in: ...Date(), displayedComponents: .date)
                ForEach(Array(stages.enumerated()), id: \.offset) { i, stage in
                    if i < passed, let b = existing {
                        pastRow(i, stage, b)
                    } else {
                        stageRow(i, stage, isNow: existing != nil && i == passed)
                    }
                }
                .onDelete { idx in
                    let removable = idx.filter { $0 >= passed }
                    stages.remove(atOffsets: IndexSet(removable))
                }
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 24, height: 24)
                    Text("Then \(PlanHistory.lowered(Engine.everyPhrase(goal, word: word)))")
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("your goal").font(.footnote).foregroundStyle(Palette.ink3)
                }
                if stages.count < 4 {
                    Button {
                        let slowest = stages.first?.every ?? 3
                        stages.insert(BuildStage(every: min(4, slowest + 1), days: 14), at: passed)
                    } label: {
                        Label("Add a slower stage", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.accent)
                    }
                    .disabled((stages.first?.every ?? 3) >= 4 || passed > 0)
                }
                if let b = existing, !b.done {
                    Button(action: moveUpNow) {
                        Label(b.stage + 1 < b.stages.count
                              ? "Move up to \(PlanHistory.lowered(Engine.everyPhrase(b.stages[b.stage + 1].every, word: word))) now"
                              : "Move up to \(PlanHistory.lowered(Engine.everyPhrase(b.goal, word: word))) now",
                              systemImage: "arrow.up.circle.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
        } header: {
            Text("Starting it")
        } footer: {
            if on {
                Text("Already doing it? Set the date you started, and the weeks count from then. Tendwell asks how your skin is before each move up, and dates every move for your report.")
            } else {
                Text("Dermatologists often start retinoids and acids 2–3 times a week, then build up if your skin is OK.")
            }
        }
    }

    private func pastRow(_ i: Int, _ stage: BuildStage, _ b: BuildUp) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.ink3)
                .frame(width: 24, height: 24)
                .background(Palette.fill, in: Circle())
            Text(Engine.everyPhrase(stage.every, word: slot.word)).foregroundStyle(Palette.ink3)
            Spacer()
            Text("\(b.stageStart(i).short) – \(b.stageStart(i + 1).short)")
                .font(.footnote.monospacedDigit()).foregroundStyle(Palette.ink3)
        }
        .deleteDisabled(true)
    }

    private func stageRow(_ i: Int, _ stage: BuildStage, isNow: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(i + 1)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(isNow ? Color(hex: 0xFFFDF9) : Palette.ink)
                .frame(width: 24, height: 24)
                .background(isNow ? Palette.ink : Palette.fill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Picker("How often", selection: Binding(
                    get: { stage.every },
                    set: { v in if i < stages.count { stages[i].every = v } }
                )) {
                    ForEach([4, 3, 2].filter { $0 > goal }, id: \.self) { n in
                        Text(Engine.everyPhrase(n, word: slot.word)).tag(n)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Palette.ink)
                .fixedSize()
                .padding(.leading, -12)
                Text(isNow ? "Now · \(Engine.perWeek(stage.every))" : Engine.perWeek(stage.every))
                    .font(.caption).foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
            Picker("For", selection: Binding(
                get: { max(1, stage.days / 7) },
                set: { v in if i < stages.count { stages[i].days = v * 7 } }
            )) {
                ForEach(1...8, id: \.self) { w in Text("\(w) week\(w == 1 ? "" : "s")").tag(w) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Palette.ink2)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Add a product

struct AddProductSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var slot: Slot
    @State private var name = ""
    @State private var kind: ProductKind = .treatment
    @State private var editing: StepTarget?
    /// The step just added, briefly highlighted so you see where it landed.
    @State private var justAdded: String?

    var body: some View {
        let sp = model.state.plan[slot]
        let products = model.products
        let inSlot = Set(sp.steps.compactMap { products[$0.productId]?.name.lowercased() })
        // Morning and evening can share products; the body routine keeps its own.
        let otherFace: Slot? = slot == .am ? .pm : (slot == .pm ? .am : nil)
        let otherIDs = Set(otherFace.map { model.state.plan[$0].steps.map(\.productId) } ?? [])
        let fromOther = model.state.products.filter { otherIDs.contains($0.id) && !inSlot.contains($0.name.lowercased()) }
        let pool = Presets.pool(for: slot).filter { q in !fromOther.contains { $0.name.lowercased() == q.name.lowercased() } }
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Group {
                Section {
                    if sp.steps.isEmpty {
                        Text("Nothing yet. Tap what you use below.")
                            .foregroundStyle(Palette.ink3)
                    }
                    ForEach(sp.steps) { step in
                        if let p = products[step.productId] {
                            Button {
                                editing = StepTarget(slot: slot, stepID: step.id)
                            } label: {
                                StepRow(step: step, product: p, sp: sp, slot: slot)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(justAdded == step.id ? Palette.selected : Palette.surface)
                            .id(step.id)
                        }
                    }
                    .onMove { from, to in
                        model.update { $0.plan[slot].steps.move(fromOffsets: from, toOffset: to) }
                        Haptics.tap(model.state.settings.haptics)
                    }
                    .onDelete { idx in
                        model.editPlan(slot) { s in
                            s.plan[slot].steps.remove(atOffsets: idx)
                            s.pruneOrphanProducts()
                        }
                    }
                } header: {
                    Text("Your \(slot.name(model.state.plan).lowercased()), in order")
                } footer: {
                    if sp.steps.count > 1 {
                        Text("Drag the handles to reorder. Tap a step to set how often, the amount, or to start it slowly.")
                    }
                }
                if !fromOther.isEmpty {
                    Section("Also in your \(slot == .pm ? "morning" : "evening")") {
                        FlowLayout(spacing: 8) {
                            ForEach(fromOther) { p in
                                Chip(title: p.name, selected: false, hue: p.kind.hue, symbol: "plus") { add(existing: p, proxy: proxy) }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(pool) { q in
                            let on = inSlot.contains(q.name.lowercased())
                            Chip(title: q.name, selected: on, hue: q.kind.hue, symbol: on ? "checkmark" : "plus") {
                                if on { remove(named: q.name) } else { add(quick: q, proxy: proxy) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Common ones")
                } footer: {
                    Text("Tap to add, tap again to remove. Rename it to your exact product and strength from its step.")
                }
                Section("Something else") {
                    TextField("Name, e.g. Epiduo gel", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { add(custom: name, kind: kind, proxy: proxy) }
                    Picker("Type", selection: $kind) {
                        ForEach(ProductKind.allCases) { Text($0.label).tag($0) }
                    }
                    // The add row appears once there's a name to add.
                    let typed = name.trimmingCharacters(in: .whitespaces)
                    if !typed.isEmpty {
                        Button { add(custom: name, kind: kind, proxy: proxy) } label: {
                            Label("Add \(typed)", systemImage: "plus.circle.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
                }
                .rows()
            }
            .barrierList()
            // Reorder handles always showing: drag straight away, no hold needed.
            .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Add to \(slot.name(model.state.plan).lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .sheet(item: $editing) { t in StepEditorSheet(target: t).barrier(model) }
        }
    }

    private func remove(named n: String) {
        let products = model.products
        guard let step = model.state.plan[slot].steps.first(where: { products[$0.productId]?.name.lowercased() == n.lowercased() }) else { return }
        model.editPlan(slot) { s in
            s.plan[slot].steps.removeAll { $0.id == step.id }
            s.pruneOrphanProducts()
        }
        Haptics.tap(model.state.settings.haptics)
    }

    private func add(existing p: Product, proxy: ScrollViewProxy) {
        insert(product: p, quick: Presets.quickProducts.first { $0.name == p.name }, isNew: false, proxy: proxy)
    }

    private func add(quick q: QuickProduct, proxy: ScrollViewProxy) {
        let p = Presets.makeProduct(name: q.name, kind: q.kind, today: model.today)
        insert(product: p, quick: q, isNew: true, proxy: proxy)
    }

    private func add(custom: String, kind: ProductKind, proxy: ScrollViewProxy) {
        let n = custom.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let p = Presets.makeProduct(name: n, kind: kind, today: model.today)
        insert(product: p, quick: nil, isNew: true, proxy: proxy)
        name = ""
    }

    private func insert(product p: Product, quick q: QuickProduct?, isNew: Bool, proxy: ScrollViewProxy) {
        var unscheduled = false
        var slow = false
        var newID: String?
        model.editPlan(slot) { s in
            if isNew { s.upsertProduct(p) }
            var step = Presets.makeStep(productId: p.id, from: q)
            if p.kind == .spf && slot == .pm { step.how = nil }
            let kinds = Dictionary(s.products.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
            s.plan[slot].steps = Presets.insert(step, kind: p.kind, into: s.plan[slot].steps, kinds: kinds)
            // Retinoids go on dry skin: suggest a wait after the cleanser.
            if p.kind == .retinoid, let ci = s.plan[slot].steps.firstIndex(where: { kinds[$0.productId] == .cleanser }), s.plan[slot].steps[ci].waitMin == nil {
                s.plan[slot].steps[ci].waitMin = 20
            }
            if slot == .pm, let every = q?.every, every > 1 {
                let products = Dictionary(s.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                if let plan = Engine.setEvery(s.plan[slot], stepID: step.id, n: every, products: products) {
                    s.plan[slot] = plan
                } else if let i = s.plan[slot].steps.firstIndex(where: { $0.id == step.id }) {
                    // Doesn't fit the current rotation: add it unscheduled rather than guess.
                    s.plan[slot].steps[i].on = .nights([])
                    unscheduled = true
                }
            }
            if !s.plan[slot].enabled { s.plan[slot].enabled = true }
            newID = step.id
            // A new retinoid starts slowly, the way dermatologists start them. One tap to change.
            if isNew, p.kind == .retinoid, slot != .body, !unscheduled {
                slow = s.startBuildUp(slot, stepID: step.id, stages: Presets.buildUpStages, start: p.from.map { max($0, model.today) } ?? model.today, today: model.today)
            }
        }
        Haptics.tap(model.state.settings.haptics)
        withAnimation(Motion.ui) { justAdded = newID }
        if let id = newID {
            withAnimation { proxy.scrollTo(id, anchor: .center) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if justAdded == id { withAnimation(.easeOut(duration: 0.6)) { justAdded = nil } }
            }
        }
        if unscheduled {
            model.show("Added \(p.name). Tap it to choose its nights.")
        } else if slow {
            model.show("Added \(p.shortName), starting slowly: every 3rd night. Tap it to change.")
        }
    }
}
