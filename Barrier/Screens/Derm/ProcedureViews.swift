import BarrierCore
import SwiftUI

// Procedures: subcision, laser, peels, microneedling, injections. Logged with
// the clinic's own dates and notes, paired with before and after photos.

/// What the add/edit sheet is working on.
struct ProcedureEdit: Identifiable {
    var procedure: Procedure
    var isNew: Bool
    var id: String { procedure.id }

    static func new(on day: Day) -> ProcedureEdit {
        ProcedureEdit(procedure: Procedure(name: "", day: day), isNew: true)
    }
}

extension Day {
    /// "Today", "Yesterday", "5 days ago", "3 weeks ago", "4 months ago".
    func ago(from today: Day) -> String {
        let n = days(to: today)
        switch n {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<14: return "\(n) days ago"
        case 14..<120: return "\(n / 7) weeks ago"
        default: return "\(n / 30) months ago"
        }
    }

    /// "Today", "Tomorrow", "In 5 days".
    func ahead(from today: Day) -> String {
        let n = today.days(to: self)
        switch n {
        case ..<1: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(n) days"
        }
    }
}

extension ComparePair {
    /// A procedure's before and after, titled for it.
    static func procedure(_ p: Procedure, before: PhotoMeta, after: PhotoMeta) -> ComparePair {
        let gap = Procedures.since(p.day.days(to: after.day)).lowercased()
        return ComparePair(before: before, after: after, title: p.name, caption: "Before and \(gap). Drag to compare.")
    }
}

/// A small calendar tile: "OCT" over "15".
struct DateTile: View {
    var day: Day
    var upcoming: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(day.date().formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(upcoming ? Palette.accent : Palette.ink3)
            Text("\(day.day)")
                .font(.barrierH3)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .frame(width: 44, height: 46)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Derm tab section

struct ProceduresSection: View {
    @Environment(AppModel.self) private var model
    @Binding var editing: ProcedureEdit?
    @State private var showAll = false

    var body: some View {
        let today = model.today
        let upcoming = Procedures.upcoming(model.state, today: today)
        let past = Procedures.past(model.state, today: today)
        Section {
            ForEach(upcoming) { p in row(p, upcoming: true) }
            ForEach(showAll ? past : Array(past.prefix(4))) { p in row(p, upcoming: false) }
            if past.count > 4 && !showAll {
                Button("Show all \(past.count) past procedures") { showAll = true }
            }
            Button {
                editing = .new(on: today)
            } label: {
                // The plus sits in the date-tile column, so the text lines up with the titles.
                HStack(spacing: 12) {
                    Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 44)
                    Text("Add a procedure")
                }
                .foregroundStyle(Palette.ink)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 56 }
        } header: {
            Text("Procedures")
        } footer: {
            Text(upcoming.isEmpty && past.isEmpty
                 ? "Subcision, laser, peels, microneedling, injections. Barrier reminds you the evening before and pairs your before and after photos."
                 : "Tap one for its notes and before and after photos.")
        }
    }

    private func row(_ p: Procedure, upcoming: Bool) -> some View {
        Button {
            editing = ProcedureEdit(procedure: p, isNew: false)
        } label: {
            HStack(spacing: 12) {
                DateTile(day: p.day, upcoming: upcoming)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.body.weight(.medium)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Text(detail(p, upcoming: upcoming)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    if !upcoming, Procedures.afterPhoto(p, in: model.state) != nil {
                        Label("Before and after", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.ink3)
                            .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        // Separators start at the title, not under the date tile.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 56 }
    }

    private func detail(_ p: Procedure, upcoming: Bool) -> String {
        let when = upcoming ? p.day.ahead(from: model.today) : p.day.ago(from: model.today)
        let area = p.place == .body ? model.bodyAreaName : nil
        return ([when, p.spot ?? area, p.clinic].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: " · ")
    }
}

// MARK: - Add / edit

struct ProcedureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    @State private var p: Procedure
    @State private var inSeries: Bool
    @State private var hasBreak: Bool
    @State private var confirmDelete = false
    @State private var compare: ComparePair?
    @State private var camera: Area?
    @State private var viewing: PhotoMeta?
    /// Fields filled in from an earlier session; only until the user edits them.
    @State private var prefilled = false

    init(edit: ProcedureEdit) {
        isNew = edit.isNew
        _p = State(initialValue: edit.procedure)
        _inSeries = State(initialValue: edit.procedure.session != nil)
        _hasBreak = State(initialValue: edit.procedure.breakDays != nil)
    }

    private var today: Day { model.today }
    private var bodyName: String { model.state.plan.body.displayName }
    private var trimmedName: String { p.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The saved version, for photos (the sheet's edits aren't saved yet).
    private var saved: Procedure? { model.state.procedures.first { $0.id == p.id } }
    /// A break needs a routine to take actives out of: none for the body without a body routine.
    private var breakApplies: Bool { p.place == .face || model.hasBodyRoutine }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if let saved { photosSection(saved) }
                    detailsSection
                    seriesSection
                    if breakApplies { breakSection }
                    aftercareSection
                    if Procedures.takesIsotretinoin(model.state) && p.day >= today {
                        Section {
                            noteRow(Guidance.isotretinoin)
                        }
                    }
                    if Procedures.sunCare(p.name) {
                        Section {
                            noteRow(Guidance.procedureSun)
                        }
                    }
                    if !isNew {
                        Section {
                            Button("Delete procedure", role: .destructive) { confirmDelete = true }
                        }
                    }
                }
                .rows()
            }
            .barrierList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "New procedure" : p.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedName.isEmpty).tint(Palette.accent)
                }
            }
            .confirmationDialog("Delete this procedure?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.update { $0.removeProcedure(p.id, today: model.today) }
                    model.show("Procedure deleted. Your photos are still in Progress.")
                    dismiss()
                }
            } message: {
                Text("Photos stay in Progress. Days of a break that already happened stay in your history.")
            }
            .sheet(item: $compare) { pair in CompareView(pair: pair).barrier(model) }
            .sheet(item: $viewing) { photo in PhotoDetail(photo: photo).barrier(model) }
            .fullScreenCover(item: $camera) { area in CameraScreen(initialArea: area).barrier(model) }
        }
    }

    // MARK: Photos

    @ViewBuilder
    private func photosSection(_ saved: Procedure) -> some View {
        let s = model.state
        let before = Procedures.beforePhoto(saved, in: s)
        let after = Procedures.afterPhoto(saved, in: s)
        // Today or later: the before photo should be a fresh one.
        let ahead = saved.day >= today
        Section {
            HStack(alignment: .top, spacing: 10) {
                slot("Before", photo: ahead ? Procedures.recentBefore(saved, in: s) : before, canTake: ahead, area: saved.place)
                slot("After", photo: after, canTake: !ahead, area: saved.place)
                    .opacity(ahead ? 0.45 : 1)
            }
            .padding(.vertical, 4)
            if let before, let after {
                Button {
                    compare = .procedure(saved, before: before, after: after)
                } label: {
                    Label("Compare before and after", systemImage: "rectangle.split.2x1")
                }
            }
            let series = Procedures.series(saved, in: s)
            if let first = series.first, first.id != saved.id, let b = Procedures.beforePhoto(first, in: s), let a = after, b.id != a.id {
                Button {
                    compare = ComparePair(before: b, after: a, title: saved.name,
                                          caption: "Before session 1 (\(first.day.short)) and the latest (\(a.day.short)). Drag to compare.")
                } label: {
                    Label("Compare with before session 1", systemImage: "clock.arrow.circlepath")
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text(photoFooter(saved, before: before, after: after))
        }
    }

    private func photoFooter(_ saved: Procedure, before: PhotoMeta?, after: PhotoMeta?) -> String {
        if saved.day >= today {
            return Guidance.procedurePhotos.body
        }
        if after == nil {
            // Only the latest procedure on an area gets the photo reminders.
            let latest = Procedures.past(model.state, today: today.adding(1)).first { $0.place == saved.place }?.id == saved.id
            return latest ? "Take an after photo in the same light. Barrier reminds you at 4 weeks, 12 weeks and 6 months." : "Take an after photo in the same light."
        }
        return Procedures.scarTreatment(saved.name) ? Guidance.procedureGradual.body
            : "Paired by date: the last photo before, and the latest one since (or the one before your next session)."
    }

    @ViewBuilder
    private func slot(_ title: String, photo: PhotoMeta?, canTake: Bool, area: Area) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let photo {
                PhotoThumb(photo: photo)
                    .onTapGesture { viewing = photo }
            } else {
                Button {
                    camera = area
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface2)
                        VStack(spacing: 6) {
                            Image(systemName: canTake ? "camera" : "photo").font(.title3)
                            Text(canTake ? "Take photo" : "No photo yet").font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(canTake ? Palette.ink : Palette.ink3)
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .disabled(!canTake)
            }
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Details

    private var detailsSection: some View {
        Section {
            HStack {
                TextField("Name, e.g. Subcision", text: $p.name)
                    .textInputAutocapitalization(.sentences)
                Menu {
                    ForEach(Procedures.names, id: \.self) { n in
                        Button(n) { p.name = n }
                    }
                } label: {
                    Image(systemName: "list.bullet").frame(width: 36, height: 32)
                }
                .accessibilityLabel("Common procedures")
            }
            if isNew && trimmedName.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(["Subcision", "Microneedling", "Chemical peel", "Fractional CO2 laser", "IPL", "Cortisone injection"], id: \.self) { n in
                        Chip(title: n, selected: false) { p.name = n }
                    }
                }
                .padding(.vertical, 4)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            DatePicker("Date", selection: Binding(
                get: { p.day.date() },
                set: { p.day = Day(date: $0) }
            ), displayedComponents: .date)
            Picker("Area", selection: Binding(
                get: { p.place },
                set: { p.area = $0 == .face ? nil : $0 }
            )) {
                Text("Face").tag(Area.face)
                Text(model.bodyAreaName).tag(Area.body)
            }
            .pickerStyle(.segmented)
            TextField("Where exactly (optional)", text: optional(\.spot))
            TextField("Clinic or doctor (optional)", text: optional(\.clinic))
        } header: {
            Text("Procedure")
        }
        .onChange(of: p.name) { _, _ in prefillFromEarlierSession() }
        .onChange(of: p.area) { _, _ in prefillFromEarlierSession() }
    }

    /// A new session of something done before: carry over the clinic, spot and count.
    private func prefillFromEarlierSession() {
        guard isNew else { return }
        let key = trimmedName.lowercased()
        guard !key.isEmpty, let last = model.state.procedures
            .filter({ $0.place == p.place && $0.name.lowercased() == key && $0.day <= p.day })
            .max(by: { $0.day < $1.day }) else {
            if prefilled { clearPrefill() }
            return
        }
        if (p.clinic ?? "").isEmpty { p.clinic = last.clinic }
        if (p.spot ?? "").isEmpty { p.spot = last.spot }
        if !inSeries || prefilled {
            inSeries = true
            p.session = (last.session ?? 1) + 1
            p.sessions = last.sessions
        }
        prefilled = true
    }

    private func clearPrefill() {
        prefilled = false
        inSeries = false
        p.session = nil
        p.sessions = nil
    }

    private var seriesSection: some View {
        Section {
            Toggle("One of several sessions", isOn: Binding(
                get: { inSeries },
                set: { on in
                    inSeries = on
                    prefilled = false
                    if on && p.session == nil { p.session = 1 }
                }
            ))
            if inSeries {
                Stepper("Session \(p.session ?? 1)", value: Binding(
                    get: { p.session ?? 1 },
                    set: { p.session = $0; prefilled = false }
                ), in: 1...30)
                Stepper(p.sessions.map { "Planned: \($0)" } ?? "Planned: not sure", value: Binding(
                    get: { p.sessions ?? 0 },
                    set: { p.sessions = $0 == 0 ? nil : $0; prefilled = false }
                ), in: 0...30)
            }
        } footer: {
            if inSeries {
                Text("Your clinic decides how many sessions and how far apart.")
            }
        }
    }

    // MARK: Actives break

    private var breakSection: some View {
        Section {
            Toggle("My clinic asked me to pause actives", isOn: Binding(
                get: { hasBreak },
                set: { on in
                    hasBreak = on
                    if on && p.breakDays == nil {
                        p.breakBefore = 0
                        p.breakAfter = 0
                    }
                }
            ))
            if hasBreak {
                Stepper(p.breakBefore == 0 ? "Before: from the day itself" : "Before: \(span(p.breakBefore ?? 0))",
                        onIncrement: { p.breakBefore = up(p.breakBefore ?? 0, max: 63) },
                        onDecrement: { p.breakBefore = down(p.breakBefore ?? 0) })
                Stepper(p.breakAfter == 0 ? "After: back on the next day" : "After: \(span(p.breakAfter ?? 0))",
                        onIncrement: { p.breakAfter = up(p.breakAfter ?? 0, max: 91) },
                        onDecrement: { p.breakAfter = down(p.breakAfter ?? 0) })
                if let w = p.breakDays {
                    Text(breakSummary(from: w.from, to: w.to))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Actives break")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Guidance.procedureBreak.body)
                if hasBreak, let w = p.breakDays, w.from < today {
                    Text("Days before today stay as you logged them.")
                }
            }
        }
    }

    /// Day by day up to two weeks, then a week at a time: clinics often say "4 weeks".
    private func up(_ v: Int, max m: Int) -> Int { v < 14 ? v + 1 : min(m, (v / 7 + 1) * 7) }
    private func down(_ v: Int) -> Int { v <= 14 ? max(0, v - 1) : max(14, (v - 1) / 7 * 7) }
    private func span(_ d: Int) -> String { d >= 14 && d % 7 == 0 ? "\(d / 7) weeks" : "\(d) day\(d == 1 ? "" : "s")" }

    private func breakSummary(from: Day, to: Day) -> String {
        let routines = p.place == .face ? "your face routines" : "your \(bodyName.lowercased()) routine"
        let span = from == to ? "on \(from.short)" : "from \(from.short) to \(to.short)"
        return "Retinoids, acids and treatments come out of \(routines) \(span). The basics stay. Back on \(to.adding(1).short)."
    }

    // MARK: Aftercare

    private var aftercareSection: some View {
        Section {
            TextField("In their words, e.g. gentle cleanser only", text: optional(\.note), axis: .vertical)
                .lineLimit(2...8)
        } header: {
            Text("Clinic’s aftercare")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shown on Today for two weeks after. \(Guidance.procedureContact)")
                if p.day > today && model.state.settings.remindersOn {
                    Text("You’ll get a reminder at 6 PM the evening before.")
                }
            }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title).font(.subheadline.weight(.semibold))
            Text(note.body).font(.footnote).foregroundStyle(.secondary)
            SourcesView(sources: note.sources)
        }
        .padding(.vertical, 2)
    }

    private func optional(_ key: WritableKeyPath<Procedure, String?>) -> Binding<String> {
        Binding(get: { p[keyPath: key] ?? "" }, set: { p[keyPath: key] = $0 })
    }

    // MARK: Save

    private func save() {
        var out = p
        out.name = trimmedName
        func clean(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        out.spot = clean(out.spot)
        out.clinic = clean(out.clinic)
        out.note = clean(out.note)
        if !inSeries {
            out.session = nil
            out.sessions = nil
        }
        if !hasBreak || !breakApplies {
            out.breakBefore = nil
            out.breakAfter = nil
        }
        let hadBreak = saved?.breakDays != nil
        model.update { $0.saveProcedure(out, today: model.today) }
        if out.breakDays != nil && !hadBreak && out.breakDays!.to >= today {
            model.show("Saved. Actives break set.")
        } else {
            model.show(isNew ? "\(out.name) saved." : "Saved.")
        }
        dismiss()
    }
}

// MARK: - Today card

struct ProcedureCard: View {
    @Environment(AppModel.self) private var model
    var moment: ProcedureMoment
    @Binding var camera: Area?
    @State private var editing: ProcedureEdit?

    var body: some View {
        let p = moment.procedure
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Kicker(kicker, color: isSoon ? Palette.ink : Palette.ink3)
                Spacer()
                // The after-photo card hides with "Not now"; one way is enough.
                if isAfter, let id = moment.dismissID {
                    Button {
                        model.update { $0.dismiss(id) }
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Palette.ink3).frame(width: 44, height: 44)
                    }
                    .padding(.vertical, -14)
                    .padding(.trailing, -12)
                    .accessibilityLabel("Hide")
                }
            }
            Text(title(p)).font(.barrierH2).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            if let sub = subtitle(p) {
                Text(sub).font(.subheadline).foregroundStyle(Palette.ink2)
            }
            content(p)
            buttons(p).padding(.top, 4)
        }
        .card()
        .sheet(item: $editing) { e in ProcedureSheet(edit: e).barrier(model) }
    }

    private var isSoon: Bool {
        if case .upcoming(_, let n) = moment { return n <= 1 }
        return false
    }

    private var isAfter: Bool {
        if case .after = moment { return true }
        return false
    }

    private var kicker: String {
        switch moment {
        case .upcoming(let p, let n):
            return n <= 1 ? p.day.ahead(from: model.today) : "\(p.day.ahead(from: model.today)) · \(p.day.weekdayShort)"
        case .after(_, let d): return "Day \(d) after"
        case .photo(_, let w): return "\(Procedures.photoMark(w)) after"
        }
    }

    private func title(_ p: Procedure) -> String {
        switch moment {
        case .photo: return "Time for an after photo"
        default: return p.title
        }
    }

    private func subtitle(_ p: Procedure) -> String? {
        switch moment {
        case .photo: return p.title
        default:
            let area = p.place == .body ? model.bodyAreaName : nil
            let parts = [p.spot ?? area, p.clinic].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private func content(_ p: Procedure) -> some View {
        let today = model.today
        switch moment {
        case .upcoming(_, let n):
            // On the day itself, the clinic's aftercare matters from the evening on.
            if n == 0, let note = p.note { noteBox(note) }
            // A break already on shows in the banner at the top of Today.
            if let w = p.breakDays, w.from > today {
                line("pause.circle", "Actives break from \(w.from.relative(to: today, evening: false)), as your clinic asked.")
            }
            if let b = Procedures.recentBefore(p, in: model.state) {
                line("checkmark.circle", "Before photo taken \(b.day == today ? "today" : b.day.short).")
            } else {
                line("camera", n == 0 ? "Before your appointment, take a before photo if you can." : "If you can, take a before photo in good light.")
            }
            if Procedures.takesIsotretinoin(model.state) && p.day > today {
                line("exclamationmark.circle", Guidance.isotretinoin.body)
            }
        case .after:
            if let note = p.note { noteBox(note) }
            if Procedures.sunCare(p.name) {
                line("sun.max", "Sun protection matters on treated skin. Follow your clinic’s advice on how long.")
            }
            line("cross.case", p.note == nil ? Guidance.procedureContact : "Contact your clinic if something looks or feels wrong.")
        case .photo:
            line("camera.aperture", "A photo in the same light as your before one makes any change easier to see.")
            if Procedures.scarTreatment(p.name) {
                line("clock", "Scar treatments usually work gradually over weeks to months.")
            }
        }
    }

    /// The clinic's own words, set apart.
    private func noteBox(_ note: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(Palette.accent.opacity(0.6)).frame(width: 3)
            Text(note).font(.subheadline).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func buttons(_ p: Procedure) -> some View {
        // One secondary action, everything else as text.
        HStack(spacing: 16) {
            switch moment {
            case .upcoming:
                if Procedures.recentBefore(p, in: model.state) == nil {
                    Button("Before photo") { camera = p.place }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
                Button("Details") { editing = ProcedureEdit(procedure: p, isNew: false) }
                    .buttonStyle(TertiaryButtonStyle())
            case .after:
                Button("Details") { editing = ProcedureEdit(procedure: p, isNew: false) }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
            case .photo:
                Button("Open camera") { camera = p.place }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                Button("Not now") {
                    if let id = moment.dismissID { model.update { $0.dismiss(id) } }
                }
                .buttonStyle(TertiaryButtonStyle())
            }
        }
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(Palette.ink3).frame(width: 18)
            Text(text).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
