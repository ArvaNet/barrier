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
    @State private var dimmed = false
    /// Bumped on every touch during a wait, to restart the dim countdown.
    @State private var touch = 0
    /// Which way the steps are moving, so Back returns along the path it came.
    @State private var forward = true

    private var inst: Instance { model.instance(request.slot, on: request.day) }
    private var steps: [DueStep] { inst.steps }
    private var isNight: Bool { request.slot.isDusk(model.state.plan[request.slot]) }

    /// Secondary text that stays readable on the stage (and on the day background).
    private var hint: Color { isNight ? Palette.stageInk2 : Palette.ink2 }

    /// Forward: in from the right, out to the left. Back reverses it. Reduce Motion: a cross-fade.
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return forward
            ? .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))
            : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity))
    }

    var body: some View {
        ZStack {
            // A flat, calm stage. No glow.
            (isNight ? Palette.stage : Palette.bg).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if finished, let done = finishedInstance {
                    RitualFinish(inst: done, close: close)
                } else if steps.isEmpty {
                    Spacer()
                    Text("Nothing to do here.").foregroundStyle(hint)
                    Spacer()
                } else if let ends = p.waitEnds {
                    waiting(ends)
                } else {
                    stepView(min(p.index, steps.count - 1))
                }
            }
            .padding(.horizontal, 24)
            // Bedtime dim: after a quiet stretch on the wait, the screen stops lighting the room.
            if dimmed {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { wake() }
                    .transition(.opacity)
                    .accessibilityLabel("Screen dimmed. Tap to brighten.")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .environment(\.colorScheme, isNight ? .dark : (model.state.settings.theme.scheme(at: model.now) ?? .light))
        .onAppear {
            if !loaded {
                p = RitualMemory.shared.progress[request.id] ?? RitualProgress()
                loaded = true
                // Screenshot hooks (demo only).
                if model.launch.demo, steps.count > 1 {
                    if model.launch.screen == "ritual-wait" {
                        p = RitualProgress(index: 1, ticked: [steps[0].step.id], waitEnds: Date().addingTimeInterval(17 * 60 + 42), waitTotal: 20 * 60)
                    } else if model.launch.screen == "ritual-done" {
                        DispatchQueue.main.async { finish() }
                    }
                }
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
                // A glass circle whose edge sits on the 24 pt line.
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityLabel("Close")
            // Progress lives in the ring now; the bar stays quiet.
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.top, 4)
    }

    /// One fixed slot at the bottom: the main button, then a row of text actions.
    /// The same height on every step and on the wait, so nothing jumps.
    private func bottomSlot<Main: View, Left: View, Right: View>(@ViewBuilder main: () -> Main,
                                                                 @ViewBuilder left: () -> Left,
                                                                 @ViewBuilder right: () -> Right) -> some View {
        VStack(spacing: 10) {
            main().frame(height: 52)
            HStack {
                left()
                Spacer()
                right()
            }
            .buttonStyle(TertiaryButtonStyle())
            .frame(height: 44)
        }
        .padding(.bottom, 8)
    }

    private func stepView(_ i: Int) -> some View {
        let s = steps[i]
        let isLast = i == steps.count - 1
        let after = isLast ? nil : steps[i + 1]
        return VStack(spacing: 0) {
            Spacer(minLength: 12)
            // Centered on the ring, like the wait and the finish: the ring stays put and fills
            // in, only the words move. If a long note doesn't fit (small phone, large text),
            // the ring steps aside, then the words scroll.
            ViewThatFits(in: .vertical) {
                VStack(spacing: 32) {
                    StepRingView(count: steps.count, index: i, hue: inst.hue, symbol: s.product.kind.symbol)
                    stepText(s, index: i, isLast: isLast)
                }
                stepText(s, index: i, isLast: isLast)
                ScrollView { stepText(s, index: i, isLast: isLast) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            Spacer(minLength: 12)
            Group {
                if let after {
                    Text("Up next · \(after.product.name)")
                } else if steps.count > 1 {
                    Text("Last step")
                }
            }
            .font(.footnote)
            .foregroundStyle(hint)
            .padding(.bottom, 10)
            bottomSlot {
                Button("Done") { complete(i) }
                    .buttonStyle(PrimaryButtonStyle(fill: isNight ? Palette.stageAccent : Palette.accent))
            } left: {
                if i > 0 { Button("Back") { forward = false; withAnimation(Motion.ui(reduceMotion)) { p.index = i - 1 } } }
            } right: {
                Button(isLast ? "Skip" : "Skip this step") { skip(i) }
            }
        }
        .animation(Motion.ui(reduceMotion), value: p.index)
    }

    /// The step in words, centered under the ring.
    private func stepText(_ s: DueStep, index i: Int, isLast: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if s.active { HueDot(hue: inst.hue, size: 8) }
                Kicker(steps.count > 1 ? "\(inst.label) · step \(i + 1) of \(steps.count)" : inst.label, color: hint)
            }
            Text(s.product.name)
                .font(.barrierLargeTitle).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
            if let a = s.step.amount, !a.isEmpty {
                Text(a).font(.title3).foregroundStyle(Color.primary.opacity(0.9))
            }
            if let h = s.step.how, !h.isEmpty {
                Text(h).font(.body).foregroundStyle(hint)
            }
            if let w = s.step.waitMin, w > 0, !isLast {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                    Text("Then wait \(w) min")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(hint)
                .padding(.top, 2)
            }
            if let note = s.product.note, !note.isEmpty {
                // Their words, in a card of their own.
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Your dermatologist", color: hint)
                    Text(note).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: Metrics.compactRadius, style: .continuous))
                .padding(.top, 10)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .id(s.step.id)
        .transition(stepTransition)
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
                Text("Up next · \(next.product.name)").font(.subheadline).foregroundStyle(hint)
                Text("You can lock your phone. Tendwell will ping you.")
                    .font(.footnote).foregroundStyle(hint).padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            Spacer()
            bottomSlot {
                Color.clear
            } left: {
                EmptyView()
            } right: {
                Button("Skip the wait") { endWait() }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { wake() }
        .task(id: ends) {
            let delay = ends.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, p.waitEnds == ends else { return }
            Haptics.success(model.state.settings.haptics)
            endWait()
        }
        .task(id: touch) {
            // Ten quiet seconds, then dim.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, p.waitEnds != nil else { return }
            withAnimation(.easeInOut(duration: 1.2)) { dimmed = true }
        }
    }

    private func wake() {
        if dimmed { withAnimation(.easeOut(duration: 0.3)) { dimmed = false } }
        touch += 1
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
            TimerActivity.start(ritualID: request.id, title: inst.label, hue: inst.hue, reason: reason, endsAt: ends, nextStep: next.product.name)
            NotificationService.shared.scheduleTimer(at: ends, title: "Time for \(next.product.name)", body: "Your \(wait)-minute wait is over.", ritualID: request.id)
        } else {
            forward = true
            withAnimation(Motion.ui(reduceMotion)) { p.index = i + 1 }
        }
    }

    private func endWait() {
        TimerActivity.end(ritualID: request.id)
        NotificationService.shared.cancelTimer(ritualID: request.id)
        dimmed = false
        withAnimation { p.waitEnds = nil }
    }

    private func finish() {
        TimerActivity.end(ritualID: request.id)
        NotificationService.shared.cancelTimer(ritualID: request.id)
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
            TimerActivity.end(ritualID: request.id)
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
        let photoNight = inst.slot == .pm && model.state.settings.photoDay == inst.day.weekday && !model.state.photos.contains { $0.day == inst.day && $0.place == .face }
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
                // A crisp halo and a check: no glow.
                ZStack {
                    Circle().stroke(inst.hue.color.opacity(0.35), lineWidth: 1.5).frame(width: 126, height: 126)
                    Circle().fill(inst.hue.color).frame(width: 74, height: 74)
                    Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(Color(hex: 0x13201C))
                }
                .frame(height: 180)
                .scaleEffect(turned ? 1 : 0.85)
            }
            VStack(spacing: 8) {
                Text(inst.slot == .am ? "Morning done." : "\(inst.label) done.")
                    .font(.barrierLargeTitle)
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                if inst.slot == .pm {
                    Text(stats.nightsDone == 1 ? "Your first night. The start of something." : "\(stats.nightsDone) nights so far.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            // Calm certainty: you leave knowing exactly what's next.
            if !next.steps.isEmpty {
                let sp = model.state.plan[inst.slot]
                HStack(spacing: 10) {
                    HueDot(hue: next.hue, size: 10)
                    Text("\(next.day.relative(to: inst.day, evening: false).capitalized) · \(next.label) · \(sp.time.formatted)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: Metrics.compactRadius, style: .continuous))
                .padding(.top, 4)
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
                .buttonStyle(PrimaryButtonStyle(fill: inst.slot.isDusk(model.state.plan[inst.slot]) ? Palette.stageAccent : Palette.accent))
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Haptics.success(model.state.settings.haptics)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(Motion.momentum) { turned = true }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraScreen().barrier(model)
        }
    }
}
