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

    enum Freq: Hashable {
        case every(Int)
        case nights
        case weekdays
    }

    var body: some View {
        let sp = model.state.plan[target.slot]
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Name", text: $product.name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $product.kind) {
                        ForEach(ProductKind.allCases) { Text($0.label).tag($0) }
                    }
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
                    TextField("Exactly what they told you", text: Binding(get: { product.note ?? "" }, set: { product.note = $0 }), axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Your dermatologist’s instructions")
                }
                Section {
                    Picker("How often", selection: $freq) {
                        Text(target.slot == .pm ? "Every night" : "Every morning").tag(Freq.every(1))
                        Text("Every other \(target.slot.word)").tag(Freq.every(2))
                        Text("Every 3rd \(target.slot.word)").tag(Freq.every(3))
                        Text("Every 4th \(target.slot.word)").tag(Freq.every(4))
                        if sp.length > 1 { Text("Pick nights in the rotation").tag(Freq.nights) }
                        Text("Specific weekdays").tag(Freq.weekdays)
                    }
                    if freq == .nights {
                        FlowLayout(spacing: 8) {
                            ForEach(Engine.rotationNodes(model.state, slot: target.slot, on: model.today).filter { !$0.rest }, id: \.pos) { n in
                                Chip(title: "Night \(n.pos + 1)", selected: nights.contains(n.pos), hue: n.hue) {
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
                        Text("Barrier counts nights you actually do. Miss one and the next night picks up where you left off.")
                    }
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
                    Button("Remove from \(target.slot == .pm ? "evening" : "morning")", role: .destructive) { confirmRemove = true }
                }
            }
            .navigationTitle(product.name.isEmpty ? "Step" : product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(product.name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        originalFreq = freq
        originalNights = nights
        originalWeekdays = weekdays
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

    var body: some View {
        let inSlot = Set(model.state.plan[slot].steps.map(\.productId))
        let fromOther = model.state.products.filter { !inSlot.contains($0.id) }
        let suggestions = Presets.suggestions(for: slot, existing: model.state.products)
        NavigationStack {
            Form {
                if !fromOther.isEmpty {
                    Section("Already in your \(slot == .pm ? "morning" : "evening")") {
                        ForEach(fromOther) { p in
                            Button {
                                add(existing: p)
                            } label: {
                                HStack {
                                    if let h = p.kind.hue { HueDot(hue: h, size: 9) }
                                    Text(p.name).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Image(systemName: "plus").foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                }
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions) { q in
                            Chip(title: q.name, selected: false, hue: q.kind.hue) { add(quick: q) }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Common ones")
                } footer: {
                    Text("Tap to add. You can rename it to the exact product and strength afterwards.")
                }
                Section("Something else") {
                    TextField("Name, e.g. Epiduo gel", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $kind) {
                        ForEach(ProductKind.allCases) { Text($0.label).tag($0) }
                    }
                    Button("Add") { add(custom: name, kind: kind) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(slot == .pm ? "Add to evening" : "Add to morning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func add(existing p: Product) {
        insert(product: p, quick: Presets.quickProducts.first { $0.name == p.name }, isNew: false)
    }

    private func add(quick q: QuickProduct) {
        let p = Presets.makeProduct(name: q.name, kind: q.kind, today: model.today)
        insert(product: p, quick: q, isNew: true)
    }

    private func add(custom: String, kind: ProductKind) {
        let n = custom.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let p = Presets.makeProduct(name: n, kind: kind, today: model.today)
        insert(product: p, quick: nil, isNew: true)
        name = ""
    }

    private func insert(product p: Product, quick q: QuickProduct?, isNew: Bool) {
        var unscheduled = false
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
        }
        Haptics.tap(model.state.settings.haptics)
        model.show(unscheduled ? "Added \(p.name). Tap it to choose its nights." : "Added \(p.name).")
    }
}
