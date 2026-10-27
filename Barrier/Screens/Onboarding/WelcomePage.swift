import SwiftUI

/// The brand mark, alive: the rings draw in from the heart outward (each week of care
/// adds one), then tonight's marigold dot settles onto the outer ring and drifts slowly
/// around it. One entrance, then calm. Still with Reduce Motion.
struct GrowthRings: View {
    /// The outer ring's diameter.
    var size: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heart: CGFloat = 0
    @State private var middle: CGFloat = 0
    @State private var outer: CGFloat = 0
    @State private var dot: CGFloat = 0
    @State private var start = Date()

    // Proportions from the app icon (scripts/make-icon.swift).
    private var line: CGFloat { size * 0.0545 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let turn = reduceMotion ? 0 : (ctx.date.timeIntervalSince(start) / 90).truncatingRemainder(dividingBy: 1) * 360
            ZStack {
                ring(diameter: size, opacity: 0.30, trim: outer)
                ring(diameter: size * 0.673, opacity: 0.58, trim: middle)
                Circle()
                    .fill(Palette.brandMint)
                    .frame(width: size * 0.352, height: size * 0.352)
                    .scaleEffect(heart)
                ZStack {
                    Circle().fill(Palette.marigold.opacity(0.22)).frame(width: size * 0.297, height: size * 0.297)
                    Circle().fill(Palette.marigold).frame(width: size * 0.194, height: size * 0.194)
                }
                .scaleEffect(dot)
                .offset(y: -size / 2)
                .rotationEffect(.degrees(turn))
            }
            .frame(width: size * 1.3, height: size * 1.3)
        }
        .accessibilityElement()
        .accessibilityLabel("Tendwell: rings that grow with every week of care.")
        .onAppear(perform: enter)
    }

    private func ring(diameter: CGFloat, opacity: Double, trim: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(Palette.brandMint.opacity(opacity), style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: diameter, height: diameter)
            // A round cap draws a dot even at zero length: hidden until the ring starts.
            .opacity(trim > 0.001 ? 1 : 0)
    }

    private func enter() {
        guard heart == 0 else { return }
        if reduceMotion {
            heart = 1; middle = 1; outer = 1; dot = 1
            return
        }
        start = Date()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { heart = 1 }
        withAnimation(.easeInOut(duration: 0.75).delay(0.18)) { middle = 1 }
        withAnimation(.easeInOut(duration: 0.9).delay(0.38)) { outer = 1 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.5).delay(1.05)) { dot = 1 }
    }
}

/// The first screen: the brand on its emerald stage, and the app explaining itself
/// as a Tonight card that ticks its own steps off.
struct WelcomePage: View {
    var onStart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardIn = false
    @State private var ticked = 0

    private let steps: [(name: String, detail: String?)] = [
        ("Gentle cleanser", nil),
        ("Adapalene", "Pea-size, on dry skin"),
        ("Moisturizer", nil),
    ]

    var body: some View {
        GeometryReader { geo in
            let stageH = min(360, geo.size.height * 0.4)
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.stageRadius, style: .continuous)
                        .fill(Palette.brand)
                    GrowthRings(size: stageH * 0.56)
                        .padding(.bottom, 34)
                }
                .frame(height: stageH)
                .padding(.top, 8)

                card
                    .padding(.horizontal, 18)
                    .padding(.top, -58)
                    .opacity(cardIn ? 1 : 0)
                    .offset(y: cardIn ? 0 : 24)

                Text("Your dermatologist’s routine, remembered.")
                    .font(.barrierLargeTitle).tracking(-0.5)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 26)
                Text("Tonight’s exact steps, a reminder at the right time, and proof it’s working.")
                    .font(.body)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                Spacer(minLength: 16)
                Button("Set up my routine", action: onStart)
                    .buttonStyle(PrimaryButtonStyle())
                Text("Everything stays on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 16)
        }
        .onAppear(perform: enter)
    }

    private var card: some View {
        let done = ticked >= steps.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker(done ? "Tonight · done" : "Tonight · 21:30")
                        .contentTransition(.opacity)
                    Text("Adapalene night").font(.barrierH2).foregroundStyle(Palette.ink)
                }
                Spacer()
                Text(done ? "Done" : "\(ticked) of \(steps.count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(done ? Palette.onCta : Palette.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(done ? Palette.marigold : Palette.fill, in: Capsule())
                    .contentTransition(.numericText())
                    .scaleEffect(done && !reduceMotion ? 1.06 : 1)
            }
            .padding(.bottom, 10)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(Palette.line2, lineWidth: 1.5)
                        if i < ticked {
                            Circle().fill(Palette.brand)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.brandMint)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(i < ticked ? Palette.ink3 : Palette.ink)
                        if let d = step.detail {
                            Text(d).font(.caption).foregroundStyle(Palette.ink3)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: tonight is an Adapalene night, three steps.")
    }

    private func enter() {
        guard !cardIn else { return }
        if reduceMotion {
            cardIn = true
            ticked = steps.count
            return
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.9)) { cardIn = true }
        // The steps tick themselves off, then the card says done: the feeling the app is for.
        for i in 1...steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 0.5) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { ticked = i }
            }
        }
    }
}
