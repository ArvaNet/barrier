import BarrierCore
import SwiftUI

struct DermView: View {
    @Environment(AppModel.self) private var model
    @State private var newQuestion = ""
    @FocusState private var questionFocused: Bool
    @State private var editing: ProcedureEdit?
    @State private var compare: ComparePair?
    @State private var showSample = false
    @State private var thumbnail: UIImage?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Group {
                    reportHero
                    followUpSection
                    ProceduresSection(editing: $editing)
                    questionsSection
                    notesSection
                    guidanceSection
                    Section {
                        Text(Guidance.disclaimer).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .rows()
            }
            .barrierList()
            .navigationTitle("Dermatologist")
            .sheet(isPresented: $model.showReport) {
                ReportView().barrier(model)
            }
            .sheet(item: $editing) { e in ProcedureSheet(edit: e).barrier(model) }
            .sheet(isPresented: $showSample) { ReportView(sample: true).barrier(model) }
            .sheet(item: $compare) { pair in CompareView(pair: pair).barrier(model) }
            .onAppear(perform: applyLaunchScreen)
        }
    }

    /// Screenshot hooks: `-screen procedure` and `-screen procedure-compare` open the demo peel.
    private func applyLaunchScreen() {
        if model.launch.screen == "sample-report" && !showSample { showSample = true }
        if model.launch.screen == "procedure-new" && editing == nil { editing = .new(on: model.today) }
        guard let screen = model.launch.screen, let peel = model.state.procedures.first(where: { $0.id == "demo-peel" }) else { return }
        switch screen {
        case "procedure":
            if editing == nil { editing = ProcedureEdit(procedure: peel, isNew: false) }
        case "procedure-compare":
            if compare == nil, let b = Procedures.beforePhoto(peel, in: model.state), let a = Procedures.afterPhoto(peel, in: model.state) {
                compare = .procedure(peel, before: b, after: a)
            }
        default: break
        }
    }

    // MARK: Report

    /// The report as the tab's first card: what the dermatologist will see, one tap away.
    private var reportHero: some View {
        let fu = model.state.plan.followUp
        let kicker = fu.map { f in "For \(f.day.short)" + (f.with.map { " · \($0)" } ?? "") } ?? "Your report"
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(kicker)
                    Text("Your visit report").font(.barrierH2).foregroundStyle(Palette.ink)
                }
                Button {
                    model.showReport = true
                } label: {
                    ReportThumbnail(image: thumbnail)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open your report")
                Text("Timeline, routine changes, skin log, procedures and photos, on paper your dermatologist can read in a minute.")
                    .font(.subheadline).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button("Open report") { model.showReport = true }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("See a sample") { showSample = true }
                        .buttonStyle(TertiaryButtonStyle())
                        .fixedSize()
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 8)
            .task(id: model.state.log.count + model.state.history.count + model.state.checkins.count + model.state.procedures.count) {
                thumbnail = renderThumbnail()
            }
        } footer: {
            if fu == nil {
                Text("Add your next visit below and Barrier reminds you the evening before, with the report ready.")
            }
        }
    }

    /// Page 1, rendered small (it is the same view the PDF uses).
    @MainActor
    private func renderThumbnail() -> UIImage? {
        let data = ReportData(state: model.state, today: model.today, photos: model.photos)
        let r = ImageRenderer(content: ReportSummaryPage(data: data).frame(width: 595, height: 842).environment(\.colorScheme, .light))
        r.scale = 1.4
        return r.uiImage
    }

    // MARK: Follow-up

    private var followUpSection: some View {
        let fu = model.state.plan.followUp
        return Section {
            Toggle("Follow-up booked", isOn: Binding(
                get: { fu != nil },
                set: { on in
                    model.update { $0.plan.followUp = on ? FollowUp(day: model.today.adding(42)) : nil }
                }
            ))
            if let fu {
                DatePicker("Date", selection: Binding(
                    get: { fu.day.date() },
                    set: { d in model.update { $0.plan.followUp?.day = Day(date: d) } }
                ), in: Date()..., displayedComponents: .date)
                TextField("Dermatologist’s name (optional)", text: Binding(
                    get: { fu.with ?? "" },
                    set: { v in model.update { $0.plan.followUp?.with = v.isEmpty ? nil : v } }
                ))
            }
        } header: {
            Text("Next visit")
        } footer: {
            if let fu {
                let n = model.today.days(to: fu.day)
                if n >= 0 {
                    Text(n == 0 ? "That’s today. Your report is ready." : "In \(n) day\(n == 1 ? "" : "s"). You’ll get a reminder the evening before.")
                }
            }
        }
    }

    // MARK: Questions

    private var questionsSection: some View {
        Section {
            ForEach(model.state.questions) { q in
                Button {
                    model.update { s in
                        if let i = s.questions.firstIndex(where: { $0.id == q.id }) { s.questions[i].answered.toggle() }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: q.answered ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(q.answered ? Palette.ok : Palette.ink3)
                        Text(q.text)
                            .foregroundStyle(q.answered ? Palette.ink3 : Palette.ink)
                            .strikethrough(q.answered)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in model.update { $0.questions.remove(atOffsets: idx) } }
            HStack {
                TextField("Add a question…", text: $newQuestion)
                    .focused($questionFocused)
                    .submitLabel(.done)
                    .onSubmit(addQuestion)
                if !newQuestion.isEmpty {
                    Button("Add", action: addQuestion).font(.body.weight(.semibold))
                }
            }
        } header: {
            Text("Questions to ask")
        } footer: {
            Text("Write them down the moment you think of them. Tick them off at the visit.")
        }
    }

    private func addQuestion() {
        let q = newQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        model.update { $0.questions.append(Question(text: q)) }
        newQuestion = ""
    }

    // MARK: Notes

    private var notesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("What they told you").font(.subheadline.weight(.semibold))
                TextField("Anything about the routine, in their words", text: Binding(
                    get: { model.state.plan.dermNotes ?? "" },
                    set: { v in model.update { $0.plan.dermNotes = v.isEmpty ? nil : v } }
                ), axis: .vertical)
                .lineLimit(3...10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("If my skin gets irritated").font(.subheadline.weight(.semibold))
                TextField("e.g. skip tretinoin 2 nights, moisturizer only", text: Binding(
                    get: { model.state.plan.ifIrritated ?? "" },
                    set: { v in model.update { $0.plan.ifIrritated = v.isEmpty ? nil : v } }
                ), axis: .vertical)
                .lineLimit(2...6)
            }
        } header: {
            Text("Your dermatologist’s words")
        } footer: {
            Text("Barrier shows the irritation plan when you log red or stinging skin.")
        }
    }

    // MARK: Guidance

    private var guidanceSection: some View {
        Section {
            ForEach(guides, id: \.title) { note in
                DisclosureGroup(note.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.body).font(.subheadline).foregroundStyle(.secondary)
                        SourcesView(sources: note.sources)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Good to know")
        } footer: {
            Text("Checked against the American Academy of Dermatology, drug labels, DermNet and NHS leaflets. Your dermatologist’s plan comes first.")
        }
    }

    private var guides: [Note] {
        var out = [
            Guidance.irritation,
            Note(title: "When to call your dermatologist", body: Guidance.callYourDerm, sources: Guidance.irritation.sources),
            Guidance.easeIn,
            Guidance.photoTips,
            Guidance.conflict(.retinoidExfoliant),
            Guidance.conflict(.bpoTretinoin),
            Guidance.skinCycling,
        ]
        // Procedure notes only once there's a procedure to go with them.
        if !model.state.procedures.isEmpty {
            out += [Guidance.procedureBreak, Guidance.procedureSun, Guidance.procedureGradual, Guidance.procedurePhotos]
            if Procedures.takesIsotretinoin(model.state) { out.append(Guidance.isotretinoin) }
        }
        return out
    }
}
