import BarrierCore
import SwiftUI

struct DermView: View {
    @Environment(AppModel.self) private var model
    @State private var newQuestion = ""
    @FocusState private var questionFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                followUpSection
                questionsSection
                notesSection
                Section {
                    Button {
                        model.showReport = true
                    } label: {
                        Label("Open your report", systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text("What you used, how often, how your skin felt, and your photos, on one page to show or send.")
                }
                guidanceSection
                Section {
                    Text(Guidance.disclaimer).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Dermatologist")
            .sheet(isPresented: $model.showReport) {
                ReportView().environment(model)
            }
        }
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
                TextField("With (e.g. Dr. Petrauskienė)", text: Binding(
                    get: { fu.with ?? "" },
                    set: { v in model.update { $0.plan.followUp?.with = v.isEmpty ? nil : v } }
                ))
                let n = model.today.days(to: fu.day)
                if n >= 0 {
                    Text(n == 0 ? "That’s today. Your report is ready." : "In \(n) day\(n == 1 ? "" : "s"). You’ll get a reminder the evening before.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Next visit")
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
        [
            Guidance.irritation,
            Note(title: "When to call your dermatologist", body: Guidance.callYourDerm, sources: Guidance.irritation.sources),
            Guidance.easeIn,
            Guidance.photoTips,
            Guidance.conflict(.retinoidExfoliant),
            Guidance.conflict(.bpoTretinoin),
            Guidance.skinCycling,
        ]
    }
}
