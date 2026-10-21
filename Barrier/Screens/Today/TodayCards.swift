import BarrierCore
import SwiftUI

// MARK: - "Last night — did it happen?"

struct ReconcileCard: View {
    @Environment(AppModel.self) private var model
    var inst: Instance

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HueDot(hue: inst.hue, size: 10)
                Kicker(inst.day.relative(to: model.today, evening: inst.slot == .pm).capitalized)
            }
            Text("\(inst.label). Did it happen?")
                .font(.barrierH2)
                .foregroundStyle(Palette.ink)
            Text(inst.slot == .pm ? "Logging it keeps tonight right: Tendwell never skips ahead." : "Logging it keeps the next one right: Tendwell never skips ahead.")
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
            HStack(spacing: 10) {
                Button("Yes, I did it") { model.markDone(inst, quiet: true) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("No") { model.markSkipped(inst) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .card()
    }
}

struct PauseBanner: View {
    @Environment(AppModel.self) private var model
    var pause: Pause

    var body: some View {
        let procedure = pause.procedureID.flatMap { id in model.state.procedures.first { $0.id == id } }
        HStack(spacing: 12) {
            Image(systemName: pause.reason == .travel ? "airplane" : "pause.circle")
                .font(.title3)
                .foregroundStyle(Palette.hueInk(.mist))
            VStack(alignment: .leading, spacing: 2) {
                Text(procedure == nil ? "\(pause.reason.label) until \(pause.to.short)" : "Actives break until \(pause.to.short)")
                    .font(.subheadline.weight(.semibold))
                Text(detail(procedure)).font(.footnote).foregroundStyle(Palette.ink3)
            }
            Spacer()
            Button("End") { model.endPause(pause) }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
        .card(tint: true)
    }

    private func detail(_ p: Procedure?) -> String {
        guard let p else { return "Basics only. Your rotation waits right where it was." }
        let scope = pause.area == .body ? "\(model.state.plan.body.displayName) routine: basics only" : "Basics only"
        return "For \(p.name), as your clinic asked. \(scope)."
    }
}

// MARK: - Week look-ahead

struct WeekCard: View {
    @Environment(AppModel.self) private var model
    var onTap: (Day) -> Void

    var body: some View {
        let today = model.today
        let slot: Slot = model.state.plan.pm.enabled && !model.state.plan.pm.steps.isEmpty ? .pm : .am
        let from = today.adding(-2)
        let to = today.adding(4)
        let tl = Engine.timeline(model.state, slot: slot, from: from, to: to, today: today)
        let byDay = Dictionary(tl.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let days = (0..<7).map { i -> (day: Day, inst: Instance?) in
            let d = from.adding(i)
            let inst = d < model.state.plan.createdAt ? nil : byDay[d]
            return (d, inst)
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Kicker("This week")
                Spacer()
                if let next = upcomingLine(slot: slot, today: today) {
                    Text(next).font(.footnote).foregroundStyle(Palette.ink3)
                }
            }
            WeekStrip(days: days, today: today, onTap: onTap, marked: Set(model.state.procedures.map { $0.day }))
        }
        .card(tint: true)
    }

    private func upcomingLine(slot: Slot, today: Day) -> String? {
        guard slot == .pm, let next = Engine.next(model.state, slot: .pm, today: today, horizon: 7, where: \.active) else { return nil }
        if next.day == today.adding(1) { return "Tomorrow: \(next.label.lowercased())" }
        return nil
    }
}

// MARK: - One card anatomy

/// Every Today card: a kicker (with an optional hide button), a Fraunces 22 title,
/// then its content. Text starts on the same 32 pt line as everything else.
struct TodayCard<Content: View>: View {
    var kicker: String
    var title: String?
    var tint = false
    var onDismiss: (() -> Void)?
    var dismissLabel = "Hide"
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Kicker(kicker)
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Palette.ink3)
                            .frame(width: 44, height: 44)
                    }
                    // A 44 pt target that doesn't push the kicker row taller.
                    .padding(.vertical, -14)
                    .padding(.trailing, -12)
                    .accessibilityLabel(dismissLabel)
                }
            }
            if let title {
                Text(title).font(.barrierH2).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .card(tint: tint)
    }
}

/// The action row at the bottom of a card: one secondary button, then text actions.
struct CardActions<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 16) { content() }
            .padding(.top, 4)
    }
}

// MARK: - The other routines

/// The routines that aren't the lead, as rows in one card.
struct AlsoTodayCard: View {
    var slots: [Slot]
    @Binding var notTonight: Instance?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker("Also today").padding(.bottom, 4)
            ForEach(Array(slots.enumerated()), id: \.element) { i, slot in
                SlotHero(slot: slot, big: false, notTonight: $notTonight)
                    .padding(.vertical, 10)
                if i < slots.count - 1 {
                    Divider().overlay(Palette.line).padding(.leading, 50)
                }
            }
        }
        .card()
    }
}

// MARK: - Check in: skin today, and the weekly overall rating

struct CheckInCard: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var area: Area = .face

    var body: some View {
        let s = model.state
        let today = model.today
        let hasBody = model.hasBodyRoutine
        let place: Area = hasBody ? area : .face
        let existing = s.checkIn(on: today, area: place)
        let selected = Set(existing?.feel ?? [])
        let irritated = selected.contains(where: \.isIrritation)
        // The weekly rating rides along when it's due (or was given today, so a wrong tap can be fixed).
        let scoreToday = s.scores.first { $0.day == today && $0.place == place }
        let showScore = (Scores.isDue(s, area: place, today: today) && !s.dismissed.contains("score-\(today.iso)")) || scoreToday != nil
        TodayCard(kicker: "Check in", title: place == .face ? "How’s your skin today?" : "How’s your \(model.bodyAreaName.lowercased()) today?") {
            if hasBody {
                Picker("Area", selection: $area) {
                    Text("Face").tag(Area.face)
                    Text(model.bodyAreaName).tag(Area.body)
                }
                .pickerStyle(.segmented)
                .onChange(of: area) { _, _ in editing = false }
                .padding(.top, 2)
            }
            if existing == nil || editing {
                FlowLayout(spacing: 8) {
                    ForEach(Feeling.allCases) { f in
                        Chip(title: f.label, selected: selected.contains(f), hue: nil) {
                            var set = selected
                            if set.contains(f) { set.remove(f) } else { set.insert(f) }
                            if f == .calm && set.contains(.calm) { set = [.calm] } else if f != .calm { set.remove(.calm) }
                            let ordered = Feeling.allCases.filter { set.contains($0) }
                            if existing == nil { editing = true }
                            model.update { $0.checkIn(today, feel: ordered, note: existing?.note, area: place) }
                            Haptics.tap(model.state.settings.haptics)
                        }
                    }
                }
                .padding(.top, 2)
                if existing != nil {
                    Button("Done") { editing = false }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            } else if let existing {
                HStack(alignment: .firstTextBaseline) {
                    Text(existing.feel.map(\.label).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink2)
                    Spacer()
                    Button("Edit") { editing = true }.buttonStyle(TertiaryButtonStyle())
                }
            }
            if irritated {
                IrritationHelp(slot: place == .body ? .body : .pm)
            }
            if showScore {
                Divider().overlay(Palette.line).padding(.vertical, 6)
                ScoreRow(area: place, picked: scoreToday?.value)
            }
        }
    }
}

/// "This week, overall": five equal tiles, 1 to 5, with the words at the ends.
struct ScoreRow: View {
    @Environment(AppModel.self) private var model
    var area: Area
    var picked: Int?

    var body: some View {
        let today = model.today
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week, overall").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                if let picked {
                    Text("Logged: \(Scores.label(picked))").font(.footnote).foregroundStyle(Palette.ink3)
                } else {
                    Button("Not now") { model.update { $0.dismiss("score-\(today.iso)") } }
                        .buttonStyle(TertiaryButtonStyle())
                        .padding(.vertical, -12)
                }
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { v in
                    let on = picked == v
                    Button {
                        model.update { $0.setScore(v, day: today, area: area) }
                        Haptics.tap(model.state.settings.haptics)
                    } label: {
                        Text("\(v)")
                            .font(.barrierH3)
                            .monospacedDigit()
                            .foregroundStyle(on ? Palette.surface : Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Palette.ink : Palette.fill, in: RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(v) of 5, \(Scores.label(v))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack {
                Text(Scores.label(1))
                Spacer()
                Text(Scores.label(5))
            }
            .font(.caption)
            .foregroundStyle(Palette.ink3)
            .accessibilityHidden(true)
            Text("Week by week, it becomes a line your dermatologist can read.")
                .font(.footnote).foregroundStyle(Palette.ink3)
        }
    }
}

struct IrritationHelp: View {
    @Environment(AppModel.self) private var model
    /// The routine to make gentle: tonight's face routine, or the body routine.
    var slot: Slot = .pm

    var body: some View {
        let inst = model.instance(slot)
        let isBody = slot == .body
        VStack(alignment: .leading, spacing: 10) {
            if !isBody, let derm = model.state.plan.ifIrritated, !derm.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Your dermatologist said")
                    Text(derm).font(.subheadline).foregroundStyle(Palette.ink)
                }
            } else {
                Text(Guidance.irritation.body).font(.footnote).foregroundStyle(Palette.ink2)
                SourcesView(sources: Guidance.irritation.sources)
            }
            if inst.hasActives && !inst.isResolved && inst.rest == nil {
                Button(isBody ? "Make today’s \(model.state.plan.body.displayName.lowercased()) gentle" : "Make tonight a recovery night") {
                    model.setRecovery(model.today, slot, on: true)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if inst.rest == .inserted {
                Label(isBody ? "Today is already a gentle day." : "Tonight is already a recovery night.", systemImage: "leaf")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ok)
            }
            Text(Guidance.callYourDerm).font(.caption).foregroundStyle(Palette.ink3)
        }
        .padding(Metrics.cardPadding)
        .background(Palette.warnSoft, in: RoundedRectangle(cornerRadius: Metrics.compactRadius + 2, style: .continuous))
    }
}

// MARK: - One "for you" card

/// Today shows one of these, the most useful first.
struct ForYouCard: View {
    @Environment(AppModel.self) private var model
    @Binding var camera: Area?

    var body: some View {
        let s = model.state
        let today = model.today
        if let r = Recaps.lastWeek(s, today: today), !s.dismissed.contains(r.id) {
            RecapCard(recap: r)
        } else if FollowUpCard.soon(s, today: today) {
            FollowUpCard()
        } else if PhotoPromptCard.shows(s, today: today) {
            PhotoPromptCard(camera: $camera)
        } else if let m = Milestones.unseen(s, today: today) {
            MilestoneCard(milestone: m)
        } else if JourneyCard.current(s, today: today) != nil {
            JourneyCard()
        } else if FollowUpCard.shows(s, today: today) {
            FollowUpCard()
        } else {
            TipCard()
        }
    }
}

// MARK: - Journey (how long you've been on an active)

struct JourneyCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let cur = JourneyCard.current(model.state, today: model.today) {
            let (product, day, note) = cur
            TodayCard(kicker: "\(product.shortName) · day \(day)", title: note.title,
                      onDismiss: { model.update { $0.dismiss(JourneyCard.id(product, day)) } }, dismissLabel: "Hide until next week") {
                Text(note.body).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                SourcesView(sources: note.sources)
            }
        }
    }

    static func id(_ p: Product, _ day: Int) -> String { "journey-\(p.id)-w\((day - 1) / 7)" }

    /// The note for the newest active, unless hidden this week.
    static func current(_ s: AppState, today: Day) -> (Product, Int, Note)? {
        let used = s.faceProductIDs
        let candidates = s.products
            .filter { used.contains($0.id) && ($0.kind == .retinoid || $0.kind == .treatment) && $0.from != nil }
            .sorted { a, b in a.kind == .retinoid && b.kind != .retinoid }
        for p in candidates {
            guard let from = p.from, from <= today else { continue }
            let day = from.days(to: today) + 1
            if let note = Guidance.journey(kind: p.kind, day: day), !s.dismissed.contains(id(p, day)) { return (p, day, note) }
        }
        return nil
    }
}

// MARK: - Photo prompt

struct PhotoPromptCard: View {
    @Environment(AppModel.self) private var model
    @Binding var camera: Area?

    var body: some View {
        let s = model.state
        let today = model.today
        let first = !s.photos.contains { $0.place == .face }
        TodayCard(kicker: first ? "Your before" : "Photo night", title: first ? "Take your first photo" : "Same spot, same light") {
            Text(first ? "In a few weeks you’ll be glad it exists." : "It takes 20 seconds, and it’s what makes the before and after work.")
                .font(.subheadline).foregroundStyle(Palette.ink2)
            CardActions {
                Button("Open camera") { camera = .face }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                Button("Not today") { model.update { $0.dismiss("photo-\(today.iso)") } }
                    .buttonStyle(TertiaryButtonStyle())
            }
        }
    }

    /// Photo night, or a week without a face photo; not when a procedure card already asks.
    static func shows(_ s: AppState, today: Day) -> Bool {
        let facePhotos = s.photos.filter { $0.place == .face }
        let tookToday = facePhotos.contains { $0.day == today }
        let lastPhoto = facePhotos.map(\.day).max()
        let photoDay = s.settings.photoDay >= 0 && today.weekday == s.settings.photoDay
        let overdue = (lastPhoto.map { $0.days(to: today) >= 8 } ?? true) && s.settings.photoDay >= 0
        return !tookToday && (photoDay || overdue) && !s.dismissed.contains("photo-\(today.iso)") && !procedureAsks(s, today)
    }

    /// A procedure card on Today already asks for a face photo.
    private static func procedureAsks(_ s: AppState, _ today: Day) -> Bool {
        guard let m = Procedures.moments(s, today: today).first, m.procedure.place == .face else { return false }
        switch m {
        case .photo: return true
        case .upcoming(let p, _): return Procedures.recentBefore(p, in: s) == nil
        case .after: return false
        }
    }
}

// MARK: - Follow-up

struct FollowUpCard: View {
    @Environment(AppModel.self) private var model
    @State private var askingQuestion = false
    @State private var question = ""

    /// A visit in the next three days comes first.
    static func soon(_ s: AppState, today: Day) -> Bool {
        guard let fu = s.plan.followUp else { return false }
        let n = today.days(to: fu.day)
        return n >= 0 && n <= 3
    }

    static func shows(_ s: AppState, today: Day) -> Bool {
        if let fu = s.plan.followUp { return fu.day >= today }
        return !s.dismissed.contains("followup-hint")
    }

    var body: some View {
        let s = model.state
        if let fu = s.plan.followUp, fu.day >= model.today {
            let n = model.today.days(to: fu.day)
            let open = s.questions.filter { !$0.answered }.count
            TodayCard(kicker: fu.with?.isEmpty == false ? fu.with! : "Dermatologist",
                      title: n == 0 ? "Follow-up today" : n == 1 ? "Follow-up tomorrow" : "Follow-up in \(n) days") {
                Text(open == 0 ? "Jot down questions as they come up. They’ll be in your report." : "\(open) question\(open == 1 ? "" : "s") saved for the visit.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                CardActions {
                    Button("Add a question") { askingQuestion = true }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                    Button("Report") { model.open(.report) }
                        .buttonStyle(TertiaryButtonStyle())
                }
            }
            .alert("Question for your dermatologist", isPresented: $askingQuestion) {
                TextField("e.g. Can I add vitamin C?", text: $question)
                Button("Save") {
                    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !q.isEmpty { model.update { $0.questions.append(Question(text: q)) } }
                    question = ""
                }
                Button("Cancel", role: .cancel) { question = "" }
            }
        } else if s.plan.followUp == nil && !s.dismissed.contains("followup-hint") {
            TodayCard(kicker: "Follow-up", title: "Got a visit booked?") {
                Text("Add the date and Tendwell gets a report ready for it.").font(.subheadline).foregroundStyle(Palette.ink2)
                CardActions {
                    Button("Add date") { model.tab = .derm }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                    Button("Hide") { model.update { $0.dismiss("followup-hint") } }
                        .buttonStyle(TertiaryButtonStyle())
                }
            }
        }
    }
}

// MARK: - Milestone

struct MilestoneCard: View {
    @Environment(AppModel.self) private var model
    var milestone: Milestone

    var body: some View {
        TodayCard(kicker: "Milestone", title: milestone.title) {
            Text(milestone.body).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            CardActions {
                Button("Nice") {
                    let reached = Milestones.reached(model.state, today: model.today).map(\.id)
                    model.update { s in
                        for id in reached where !s.milestonesSeen.contains(id) { s.milestonesSeen.append(id) }
                    }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
    }
}

// MARK: - Tip

struct TipCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let used = model.state.faceProductIDs
        let kinds = Set(model.state.products.filter { used.contains($0.id) }.map(\.kind))
        let bp = model.state.plan.body
        let bodyOn = bp.enabled && !bp.steps.isEmpty
        // With a body routine, every other day's tip is about it.
        let useBody = bodyOn && model.today.ordinal % 2 == 1
        let hasBpo = bp.steps.contains { model.product($0.productId)?.name.lowercased().contains("benzoyl") == true }
        let tip = useBody
            ? Guidance.bodyTip(hasBpo: hasBpo, dayNumber: model.today.ordinal / 2)
            : Guidance.tip(for: kinds, dayNumber: model.today.ordinal)
        TodayCard(kicker: useBody ? "Good to know · \(bp.displayName)" : "Good to know", tint: true) {
            Text(tip.text).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            if let s = tip.source { SourcesView(sources: [s]) }
        }
    }
}

// MARK: - Monday recap

struct RecapCard: View {
    @Environment(AppModel.self) private var model
    var recap: WeekRecap

    var body: some View {
        TodayCard(kicker: "Your week · \(recap.from.short) – \(recap.to.short)", title: recap.headline) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recap.lines, id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(Palette.ink2)
                }
            }
            CardActions {
                Button("Got it") { model.update { $0.dismiss(recap.id) } }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
    }
}
