import BarrierCore
import SwiftUI

/// Progress through a routine, kept while the app runs so closing and
/// reopening the ritual (or getting a phone call) resumes where you were.
struct RitualProgress: Hashable {
    var index = 0
    var ticked: [String] = []
    var waitEnds: Date?
    var waitTotal: TimeInterval = 0
}

@MainActor
final class RitualMemory {
    static let shared = RitualMemory()
    var progress: [String: RitualProgress] = [:]
}

struct RitualView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var request: RitualRequest

    @State private var p = RitualProgress()
    @State private var finished = false
    @State private var finishedInstance: Instance?
    @State private var loaded = false

    private var inst: Instance { model.instance(request.slot, on: request.day) }
    private var steps: [DueStep] { inst.steps }
    private var isNight: Bool { request.slot == .pm }

    var body: some View {
        ZStack {
            (isNight ? Palette.stage : Palette.bg).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if finished, let done = finishedInstance {
                    RitualFinish(inst: done, close: close)
                } else if steps.isEmpty {
                    Spacer()
                    Text("Nothing to do here.").foregroundStyle(.secondary)
                    Spacer()
                } else if let ends = p.waitEnds {
                    waiting(ends)
                } else {
                    stepView(min(p.index, steps.count - 1))
                }
            }
            .padding(.horizontal, 22)
        }
        .environment(\.colorScheme, isNight ? .dark : (model.state.settings.theme.scheme(at: model.now) ?? .light))
        .onAppear {
            if !loaded {
                p = RitualMemory.shared.progress[request.id] ?? RitualProgress()
                loaded = true
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if !finished { RitualMemory.shared.progress[request.id] = p }
        }
        .onChange(of: p) { _, new in
            if !finished { RitualMemory.shared.progress[request.id] = new }
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            Spacer()
            if !finished && !steps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i < p.index || (i == p.index && p.waitEnds != nil) ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: 22, height: 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(min(p.index + 1, steps.count)) of \(steps.count)")
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(.primary)
        .padding(.top, 4)
    }

    private func stepView(_ i: Int) -> some View {
        let s = steps[i]
        let isLast = i == steps.count - 1
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    if s.active { HueDot(hue: inst.hue, size: 9) }
                    Kicker("\(inst.label) · step \(i + 1) of \(steps.count)", color: .secondary)
                }
                Text(s.product.name)
                    .font(Typeface.display(40, weight: 420))
                    .fixedSize(horizontal: false, vertical: true)
                if let a = s.step.amount, !a.isEmpty {
                    Text(a).font(.title3).foregroundStyle(Color.primary.opacity(0.9))
                }
                if let h = s.step.how, !h.isEmpty {
                    Text(h).font(.body).foregroundStyle(.secondary)
                }
                if let note = s.product.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Rectangle().fill(inst.hue.color).frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Kicker("Your dermatologist", color: .secondary)
                            Text(note).font(.callout)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }
                if let w = s.step.waitMin, w > 0, !isLast {
                    Label("Then wait \(w) min", systemImage: "hourglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .id(s.step.id)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                Button(isLast ? "Done, finish" : "Done") { complete(i) }
                    .buttonStyle(PrimaryButtonStyle(fill: isNight ? Palette.stageAccent : Palette.accent))
                HStack {
                    if i > 0 {
                        Button("Back") { withAnimation { p.index = i - 1 } }
                    }
                    Spacer()
                    Button(isLast ? "Skip and finish" : "Skip this step") { skip(i) }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            }
            .padding(.bottom, 12)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: p.index)
    }

    private func waiting(_ ends: Date) -> some View {
        let next = steps[min(p.index, steps.count - 1)]
        let dry = next.product.kind == .retinoid
        return VStack(spacing: 22) {
            Spacer()
            TimerRingView(total: p.waitTotal, endsAt: ends, hue: inst.hue)
            VStack(spacing: 6) {
                Text(dry ? "Let your skin dry completely" : "Let it absorb")
                    .font(.barrierH2)
                Text("Next: \(next.product.name)").font(.subheadline).foregroundStyle(.secondary)
                Text("You can lock your phone. Barrier will ping you.")
                    .font(.footnote).foregroundStyle(.tertiary).padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            Spacer()
            Button("Skip the wait") { endWait() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .task(id: ends) {
            let delay = ends.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, p.waitEnds == ends else { return }
            Haptics.success(model.state.settings.haptics)
            endWait()
        }
    }

    // MARK: Logic

    private func complete(_ i: Int) {
        Haptics.tap(model.state.settings.haptics)
        let s = steps[i]
        if !p.ticked.contains(s.step.id) { p.ticked.append(s.step.id) }
        advance(from: i, wait: s.step.waitMin ?? 0)
    }

    private func skip(_ i: Int) {
        advance(from: i, wait: 0)
    }

    private func advance(from i: Int, wait: Int) {
        if i >= steps.count - 1 {
            finish()
            return
        }
        if wait > 0 {
            let total = TimeInterval(wait * 60)
            let ends = Date().addingTimeInterval(total)
            p.index = i + 1
            p.waitTotal = total
            p.waitEnds = ends
            let next = steps[i + 1]
            let reason = next.product.kind == .retinoid ? "Skin should be completely dry" : "Letting it absorb"
            TimerActivity.start(title: inst.label, hue: inst.hue, reason: reason, endsAt: ends, nextStep: next.product.name)
            NotificationService.shared.scheduleTimer(at: ends, title: "Time for \(next.product.name)", body: "Your \(wait)-minute wait is over.")
        } else {
            withAnimation { p.index = i + 1 }
        }
    }

    private func endWait() {
        TimerActivity.end()
        NotificationService.shared.cancelTimer()
        withAnimation { p.waitEnds = nil }
    }

    private func finish() {
        TimerActivity.end()
        NotificationService.shared.cancelTimer()
        let current = inst
        model.markDone(current, steps: p.ticked, quiet: true)
        finishedInstance = current
        RitualMemory.shared.progress[request.id] = nil
        withAnimation(.easeOut(duration: 0.4)) { finished = true }
    }

    private func close() {
        if p.waitEnds != nil && !finished {
            // Keep the timer running in the background; the notification will ping.
        } else {
            TimerActivity.end()
        }
        dismiss()
    }
}

// MARK: - Finish

struct RitualFinish: View {
    @Environment(AppModel.self) private var model
    var inst: Instance
    var close: () -> Void
    @State private var turned = false
    @State private var showCamera = false

    var body: some View {
        let nodes = Engine.rotationNodes(model.state, slot: inst.slot, on: inst.day)
        let next = model.instance(inst.slot, on: inst.day.adding(1))
        let stats = Engine.stats(model.state, today: model.today)
        let photoNight = inst.slot == .pm && model.state.settings.photoDay == inst.day.weekday && !model.state.photos.contains { $0.day == inst.day }
        VStack(spacing: 18) {
            Spacer()
            if nodes.count > 1 {
                OrbitView(
                    nodes: nodes.enumerated().map { i, n in
                        OrbitNode(hue: n.hue, state: i <= inst.pos ? .done : (n.rest ? .rest : .future))
                    },
                    current: turned ? next.pos : inst.pos,
                    size: 180,
                    showCount: false
                )
            } else {
                ZStack {
                    Circle().fill(inst.hue.color.opacity(0.4)).frame(width: 150, height: 150).blur(radius: 30)
                    Circle().fill(inst.hue.color).frame(width: 74, height: 74)
                    Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(Color(hex: 0x13201C))
                }
                .frame(height: 180)
                .scaleEffect(turned ? 1 : 0.85)
            }
            VStack(spacing: 8) {
                Text(inst.slot == .pm ? "\(inst.label) done." : "Morning done.")
                    .font(Typeface.display(32, weight: 430))
                    .multilineTextAlignment(.center)
                if inst.slot == .pm {
                    Text(stats.nightsDone == 1 ? "Your first night. The start of something." : "\(stats.nightsDone) nights so far.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !next.steps.isEmpty {
                    Text("Next: \(next.label.lowercased()) \(next.day.relative(to: inst.day, evening: inst.slot == .pm)).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if photoNight {
                Button {
                    showCamera = true
                } label: {
                    Label("Take this week’s photo", systemImage: "camera")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button("Back to today", action: close)
                .buttonStyle(PrimaryButtonStyle(fill: inst.slot == .pm ? Palette.stageAccent : Palette.accent))
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Haptics.success(model.state.settings.haptics)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { turned = true }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraScreen().environment(model)
        }
    }
}
