import BarrierCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var detailDay: Day?
    @State private var notTonight: Instance?
    @State private var showCamera = false

    var body: some View {
        let today = model.today
        let lead = model.leadSlot
        let other: Slot = lead == .pm ? .am : .pm
        NavigationStack {
            Page {
                header(today)
                ForEach(Engine.needsReconcile(model.state, today: today).prefix(1), id: \.self) { inst in
                    ReconcileCard(inst: inst)
                }
                if let pause = Engine.activePause(model.state, today) {
                    PauseBanner(pause: pause)
                }
                SlotHero(slot: lead, big: true, notTonight: $notTonight)
                if model.state.plan[other].enabled && !model.state.plan[other].steps.isEmpty {
                    SlotHero(slot: other, big: false, notTonight: $notTonight)
                }
                WeekCard(onTap: { detailDay = $0 })
                if let m = Milestones.unseen(model.state, today: today) {
                    MilestoneCard(milestone: m)
                }
                SkinCheckCard()
                JourneyCard()
                PhotoPromptCard(showCamera: $showCamera)
                FollowUpCard()
                TipCard()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $detailDay) { day in
            DayDetailSheet(day: day).barrier(model).presentationDetents([.medium, .large])
        }
        .sheet(item: $notTonight) { inst in
            NotTonightSheet(inst: inst).barrier(model).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraScreen().barrier(model)
        }
    }

    private func header(_ today: Day) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Kicker(today.long)
                Text(greeting)
                    .font(.barrierTitle)
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 6)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: model.now)
        switch h {
        case 4..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Hero card for a slot

struct SlotHero: View {
    @Environment(AppModel.self) private var model
    var slot: Slot
    var big: Bool
    @Binding var notTonight: Instance?

    var body: some View {
        let inst = model.instance(slot)
        if big {
            if slot == .pm {
                content(inst).stage()
            } else {
                content(inst).card(padding: 20)
            }
        } else {
            compact(inst)
        }
    }

    // Full card
    @ViewBuilder
    private func content(_ inst: Instance) -> some View {
        let sp = model.state.plan[slot]
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker("\(slot == .pm ? "Tonight" : "This morning") · \(sp.time.formatted)", color: .secondary)
                    Text(inst.label)
                        .font(.barrierDisplay)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let sub = subtitle(inst) {
                        Text(sub).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                orbit(inst)
            }

            switch inst.status {
            case .done:
                doneBanner(inst)
            case .skipped:
                skippedBanner(inst)
            default:
                stepsList(inst)
                notes(inst)
                actions(inst)
            }
        }
    }

    private func subtitle(_ inst: Instance) -> String? {
        var parts: [String] = []
        if inst.rest == .pause {
            parts.append("Plan paused. Basics only.")
        } else if inst.rest == .inserted {
            parts.append("Actives off so your skin can settle.")
        } else if inst.cycleLen > 1 {
            parts.append("\(slot == .pm ? "Night" : "Morning") \(inst.pos + 1) of \(inst.cycleLen)")
        }
        if inst.easing, let ease = model.state.plan[slot].easeIn {
            let week = ease.start.days(to: inst.day) / 7 + 1
            parts.append("easing in, week \(week)")
        }
        if slot == .pm, inst.rest == nil, let nextEx = nextActive(inst) {
            parts.append(nextEx)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "next retinoid Sat" when tonight isn't one.
    private func nextActive(_ inst: Instance) -> String? {
        guard !inst.hasActives else { return nil }
        guard let next = Engine.next(model.state, slot: slot, today: model.today, horizon: 10, where: \.active) else { return nil }
        let kind = next.steps.first(where: \.active)?.product
        let name = kind.map { $0.kind == .retinoid ? "retinoid" : $0.shortName.lowercased() } ?? "active"
        return "next \(name) \(next.day.relative(to: model.today))"
    }

    @ViewBuilder
    private func orbit(_ inst: Instance) -> some View {
        let nodes = Engine.rotationNodes(model.state, slot: slot, on: inst.day)
        if inst.rest == .pause || inst.rest == .inserted || nodes.count <= 1 {
            ZStack {
                Circle().fill(inst.hue.color.opacity(0.35)).frame(width: 64, height: 64).blur(radius: 14)
                Circle().fill(inst.hue.color).frame(width: 26, height: 26)
                Image(systemName: slot == .pm ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x13201C).opacity(0.75))
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
        } else {
            OrbitView(
                nodes: nodes.enumerated().map { i, n in
                    OrbitNode(hue: n.hue, state: i < inst.pos ? .done : i == inst.pos ? .current : (n.rest ? .rest : .future))
                },
                current: inst.pos,
                size: 104
            )
        }
    }

    private func stepsList(_ inst: Instance) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.primary.opacity(0.1))
            ForEach(Array(inst.steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if s.active { HueDot(hue: inst.hue, size: 7) }
                            Text(s.product.name).font(.body.weight(.medium))
                        }
                        if let a = s.step.amount, !a.isEmpty {
                            Text(a).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let w = s.step.waitMin, w > 0 {
                        Label("\(w) min", systemImage: "hourglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .padding(.vertical, 10)
                if i < inst.steps.count - 1 {
                    Divider().overlay(Color.primary.opacity(0.08))
                }
            }
            if inst.steps.isEmpty {
                Text("Nothing scheduled. Add steps in Routine.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private func notes(_ inst: Instance) -> some View {
        let visible = inst.conflicts.filter { !model.state.dismissed.contains("conflict:\($0.rawValue)") }
        ForEach(visible, id: \.self) { c in
            let note = Guidance.conflict(c)
            NoteBox(title: note.title, text: note.body, sources: note.sources, symbol: "exclamationmark.circle") {
                model.update { $0.dismiss("conflict:\(c.rawValue)") }
            }
            .padding(.top, 12)
        }
        ForEach(inst.lastDayOf, id: \.id) { p in
            NoteBox(title: "Last day of \(p.shortName)", text: "Your course ends today. Check with your dermatologist about what comes next.", sources: [], symbol: "flag.checkered", onDismiss: nil)
                .padding(.top, 12)
        }
    }

    private func actions(_ inst: Instance) -> some View {
        HStack(spacing: 10) {
            Button {
                model.ritual = RitualRequest(slot: slot, day: inst.day)
            } label: {
                Label("Start", systemImage: "play.fill").labelStyle(.titleOnly)
            }
            .buttonStyle(PrimaryButtonStyle(fill: slot == .pm ? Palette.stageAccent : Palette.accent))
            .disabled(inst.steps.isEmpty)

            Button("Done") { model.markDone(inst) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(inst.steps.isEmpty)

            Menu {
                Button { notTonight = inst } label: { Label("Not tonight…", systemImage: "moon.zzz") }
                if inst.rest == .inserted {
                    Button { model.setRecovery(inst.day, slot, on: false) } label: { Label("Back to the normal plan", systemImage: "arrow.uturn.backward") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 48, height: 52)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("More options")
        }
        .padding(.top, 18)
    }

    private func doneBanner(_ inst: Instance) -> some View {
        let next = model.instance(slot, on: inst.day.adding(1))
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(inst.hue.color).frame(width: 34, height: 34)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0x13201C))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(doneTime(inst)).font(.subheadline.weight(.semibold))
                if !next.steps.isEmpty {
                    Text("Next: \(next.label.lowercased()) \(next.day.relative(to: model.today, evening: slot == .pm))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Undo") { model.undoEntry(inst) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 18)
    }

    private func doneTime(_ inst: Instance) -> String {
        guard let at = inst.entry?.at else { return "Done" }
        return "Done at \(at.formatted(date: .omitted, time: .shortened))"
    }

    private func skippedBanner(_ inst: Instance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz").font(.title3).foregroundStyle(.secondary)
            Text(inst.hasActives ? "Skipped. Tomorrow picks up where you left off." : "Skipped. Rest nights still count.")
                .font(.subheadline)
            Spacer()
            Button("Undo") { model.undoEntry(inst) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 18)
    }

    // Compact row for the other slot
    private func compact(_ inst: Instance) -> some View {
        let sp = model.state.plan[slot]
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(inst.hue.color.opacity(inst.isDone ? 1 : 0.25)).frame(width: 36, height: 36)
                Image(systemName: inst.isDone ? "checkmark" : (slot == .pm ? "moon" : "sun.max"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(inst.isDone ? Color(hex: 0x13201C) : Palette.hueInk(inst.hue))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(slot == .pm ? "Tonight · \(inst.label)" : "This morning · \(inst.label)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(compactStatus(inst, time: sp.time)).font(.footnote).foregroundStyle(Palette.ink3)
            }
            Spacer()
            if inst.status == .pending || inst.status == .future {
                Button("Done") { model.markDone(inst) }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
            } else if inst.isResolved {
                Button("Undo") { model.undoEntry(inst) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !inst.isResolved { model.ritual = RitualRequest(slot: slot, day: inst.day) }
        }
        .card(padding: 14)
    }

    private func compactStatus(_ inst: Instance, time: ClockTime) -> String {
        switch inst.status {
        case .done: return doneTime(inst)
        case .skipped: return "Skipped"
        default: return "\(inst.steps.count) step\(inst.steps.count == 1 ? "" : "s") · \(time.formatted)"
        }
    }
}

/// A small note with optional sources and a dismiss button.
struct NoteBox: View {
    var title: String
    var text: String
    var sources: [Source]
    var symbol: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(Palette.warn).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !sources.isEmpty { SourcesView(sources: sources).padding(.top, 2) }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                }
                .accessibilityLabel("Hide note")
            }
        }
        .padding(12)
        .background(Palette.warnSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
