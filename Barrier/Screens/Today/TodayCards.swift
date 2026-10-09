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
            Text("Logging it keeps tonight right: Barrier never skips ahead.")
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
        HStack(spacing: 12) {
            Image(systemName: pause.reason == .travel ? "airplane" : "pause.circle")
                .font(.title3)
                .foregroundStyle(Palette.hueInk(.mist))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pause.reason.label) until \(pause.to.short)").font(.subheadline.weight(.semibold))
                Text("Basics only. Your rotation waits right where it was.").font(.footnote).foregroundStyle(Palette.ink3)
            }
            Spacer()
            Button("End") {
                model.update { $0.endPause(pause.id, today: model.today) }
                model.show("Welcome back. The plan is on again.")
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
        .card(padding: 14, tint: true)
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
            WeekStrip(days: days, today: today, onTap: onTap)
        }
        .card(padding: 14, tint: true)
    }

    private func upcomingLine(slot: Slot, today: Day) -> String? {
        guard slot == .pm, let next = Engine.next(model.state, slot: .pm, today: today, horizon: 7, where: \.active) else { return nil }
        if next.day == today.adding(1) { return "Tomorrow: \(next.label.lowercased())" }
        return nil
    }
}

// MARK: - Skin check-in

struct SkinCheckCard: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        let today = model.today
        let existing = model.state.checkIn(on: today)
        let selected = Set(existing?.feel ?? [])
        let irritated = selected.contains(where: \.isIrritation)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How’s your skin today?").font(.barrierH3).foregroundStyle(Palette.ink)
                Spacer()
                if existing != nil && !editing {
                    Button("Edit") { editing = true }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                }
            }
            if existing == nil || editing {
                FlowLayout(spacing: 8) {
                    ForEach(Feeling.allCases) { f in
                        Chip(title: f.label, selected: selected.contains(f), hue: nil) {
                            var set = selected
                            if set.contains(f) { set.remove(f) } else { set.insert(f) }
                            if f == .calm && set.contains(.calm) { set = [.calm] } else if f != .calm { set.remove(.calm) }
                            let ordered = Feeling.allCases.filter { set.contains($0) }
                            model.update { $0.checkIn(today, feel: ordered, note: existing?.note) }
                            Haptics.tap(model.state.settings.haptics)
                        }
                    }
                }
                if existing != nil {
                    Button("Save") { editing = false }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            } else if let existing {
                Text(existing.feel.map(\.label).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
            }
            if irritated {
                IrritationHelp()
            }
        }
        .card()
    }
}

struct IrritationHelp: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tonight = model.instance(.pm)
        VStack(alignment: .leading, spacing: 10) {
            if let derm = model.state.plan.ifIrritated, !derm.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Your dermatologist said")
                    Text(derm).font(.subheadline).foregroundStyle(Palette.ink)
                }
            } else {
                Text(Guidance.irritation.body).font(.footnote).foregroundStyle(Palette.ink2)
                SourcesView(sources: Guidance.irritation.sources)
            }
            if tonight.hasActives && !tonight.isResolved && tonight.rest == nil {
                Button("Make tonight a recovery night") {
                    model.setRecovery(model.today, .pm, on: true)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if tonight.rest == .inserted {
                Label("Tonight is already a recovery night.", systemImage: "leaf")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ok)
            }
            Text(Guidance.callYourDerm).font(.caption).foregroundStyle(Palette.ink3)
        }
        .padding(14)
        .background(Palette.warnSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Journey (how long you've been on an active)

struct JourneyCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let cur = current {
            let (product, day, note) = cur
            let id = "journey-\(product.id)-w\((day - 1) / 7)"
            if !model.state.dismissed.contains(id) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Kicker("\(product.shortName) · day \(day)")
                        Spacer()
                        Button {
                            model.update { $0.dismiss(id) }
                        } label: {
                            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Palette.ink3).frame(width: 28, height: 28)
                        }
                        .accessibilityLabel("Hide until next week")
                    }
                    Text(note.title).font(.barrierH3).foregroundStyle(Palette.ink)
                    Text(note.body).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                    SourcesView(sources: note.sources)
                }
                .card()
            }
        }
    }

    private var current: (Product, Int, Note)? {
        let used = Set((model.state.plan.pm.steps + model.state.plan.am.steps).map(\.productId))
        let candidates = model.state.products
            .filter { used.contains($0.id) && ($0.kind == .retinoid || $0.kind == .treatment) && $0.from != nil }
            .sorted { a, b in a.kind == .retinoid && b.kind != .retinoid }
        for p in candidates {
            guard let from = p.from, from <= model.today else { continue }
            let day = from.days(to: model.today) + 1
            if let note = Guidance.journey(kind: p.kind, day: day) { return (p, day, note) }
        }
        return nil
    }
}

// MARK: - Photo prompt

struct PhotoPromptCard: View {
    @Environment(AppModel.self) private var model
    @Binding var showCamera: Bool

    var body: some View {
        let s = model.state
        let today = model.today
        let tookToday = s.photos.contains { $0.day == today }
        let lastPhoto = s.photos.map(\.day).max()
        let photoDay = s.settings.photoDay >= 0 && today.weekday == s.settings.photoDay
        let overdue = (lastPhoto.map { $0.days(to: today) >= 8 } ?? true) && s.settings.photoDay >= 0
        if !tookToday && (photoDay || overdue) && !s.dismissed.contains("photo-\(today.iso)") {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.hueInk(.mist))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.photos.isEmpty ? "Take your first photo" : "Photo night").font(.barrierH3).foregroundStyle(Palette.ink)
                    Text(s.photos.isEmpty ? "Your “before”. In a few weeks you’ll be glad it exists." : "Same spot, same light. It takes 20 seconds.")
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                    HStack(spacing: 10) {
                        Button("Open camera") { showCamera = true }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                        Button("Not today") { model.update { $0.dismiss("photo-\(today.iso)") } }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink3)
                    }
                    .padding(.top, 4)
                }
            }
            .card()
        }
    }
}

// MARK: - Follow-up

struct FollowUpCard: View {
    @Environment(AppModel.self) private var model
    @State private var askingQuestion = false
    @State private var question = ""

    var body: some View {
        let s = model.state
        if let fu = s.plan.followUp, fu.day >= model.today {
            let n = model.today.days(to: fu.day)
            let open = s.questions.filter { !$0.answered }.count
            VStack(alignment: .leading, spacing: 10) {
                Kicker(fu.with?.isEmpty == false ? fu.with! : "Dermatologist")
                Text(n == 0 ? "Follow-up today" : n == 1 ? "Follow-up tomorrow" : "Follow-up in \(n) days")
                    .font(.barrierH2)
                    .foregroundStyle(Palette.ink)
                Text(open == 0 ? "Jot down questions as they come up. They’ll be in your report." : "\(open) question\(open == 1 ? "" : "s") saved for the visit.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                HStack(spacing: 10) {
                    Button("Add a question") { askingQuestion = true }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                    Button("Report") { model.open(.report) }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
                .padding(.top, 2)
            }
            .card()
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
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 20)).foregroundStyle(Palette.ink3).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Got a follow-up booked?").font(.barrierH3).foregroundStyle(Palette.ink)
                    Text("Add the date and Barrier gets a report ready for it.").font(.subheadline).foregroundStyle(Palette.ink2)
                    HStack(spacing: 10) {
                        Button("Add date") { model.tab = .derm }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                        Button("Hide") { model.update { $0.dismiss("followup-hint") } }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink3)
                    }
                    .padding(.top, 4)
                }
            }
            .card()
        }
    }
}

// MARK: - Milestone

struct MilestoneCard: View {
    @Environment(AppModel.self) private var model
    var milestone: Milestone

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: milestone.symbol)
                .font(.system(size: 22))
                .foregroundStyle(Palette.hueInk(.gold))
                .frame(width: 30)
                .symbolEffect(.bounce, value: milestone.id)
            VStack(alignment: .leading, spacing: 6) {
                Text(milestone.title).font(.barrierH3).foregroundStyle(Palette.ink)
                Text(milestone.body).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                Button("Nice") {
                    let reached = Milestones.reached(model.state, today: model.today).map(\.id)
                    model.update { s in
                        for id in reached where !s.milestonesSeen.contains(id) { s.milestonesSeen.append(id) }
                    }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .padding(.top, 4)
            }
        }
        .card()
    }
}

// MARK: - Tip

struct TipCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let used = Set((model.state.plan.pm.steps + model.state.plan.am.steps).map(\.productId))
        let kinds = Set(model.state.products.filter { used.contains($0.id) }.map(\.kind))
        let tip = Guidance.tip(for: kinds, dayNumber: model.today.ordinal)
        VStack(alignment: .leading, spacing: 6) {
            Kicker("Good to know")
            Text(tip.text).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            if let s = tip.source { SourcesView(sources: [s]) }
        }
        .card(padding: 16, tint: true)
    }
}

// MARK: - Monday recap

struct RecapCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let r = Recaps.lastWeek(model.state, today: model.today), !model.state.dismissed.contains(r.id) {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Your week · \(r.from.short) – \(r.to.short)")
                Text(r.headline).font(.barrierH2).foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(r.lines, id: \.self) { line in
                        Text(line).font(.subheadline).foregroundStyle(Palette.ink2)
                    }
                }
                Button("Got it") { model.update { $0.dismiss(r.id) } }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .padding(.top, 4)
            }
            .card()
        }
    }
}
