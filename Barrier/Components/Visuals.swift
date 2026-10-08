import BarrierCore
import SwiftUI

struct OrbitNode: Hashable {
    enum State: Hashable { case done, current, future, rest }
    var hue: Hue
    var state: State
}

/// The signature visual: the rotation as nodes on a ring, tonight at the top.
/// When tonight changes, the ring turns forward to bring the next night up.
struct OrbitView: View {
    var nodes: [OrbitNode]
    var current: Int
    var size: CGFloat = 116
    var showCount = true

    @State private var rotation: Double = 0
    @State private var shown = 0
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var n: Int { max(1, nodes.count) }
    private var step: Double { 360 / Double(n) }

    var body: some View {
        let r = size * 0.36
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                .frame(width: r * 2, height: r * 2)
            ZStack {
                ForEach(Array(nodes.enumerated()), id: \.offset) { i, node in
                    let angle = (Double(i) * step - 90) * .pi / 180
                    let isCur = i == current
                    let d: CGFloat = isCur ? size * 0.15 : (n > 6 ? size * 0.07 : size * 0.09)
                    ZStack {
                        if isCur {
                            Circle()
                                .fill(node.hue.color.opacity(0.55))
                                .frame(width: d * 1.9, height: d * 1.9)
                                .blur(radius: d * 0.45)
                        }
                        if node.state == .future || node.state == .rest {
                            Circle()
                                .strokeBorder(node.hue.color, lineWidth: 1.6)
                                .frame(width: d, height: d)
                                .opacity(node.state == .rest ? 0.5 : 1)
                        } else {
                            Circle()
                                .fill(node.hue.color)
                                .frame(width: d, height: d)
                                .scaleEffect(isCur && breathe ? 1.08 : 1)
                        }
                    }
                    .offset(x: cos(angle) * r, y: sin(angle) * r)
                }
            }
            .rotationEffect(.degrees(rotation))
            if showCount && n > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(current + 1)").font(Typeface.display(size * 0.15, weight: 450))
                    Text("/\(n)").font(.system(size: size * 0.085, weight: .medium)).opacity(0.6)
                }
                .foregroundStyle(Color.primary.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(n > 1 ? "Night \(current + 1) of \(n)" : "Same routine every time")
        .onAppear {
            shown = current
            rotation = -Double(current) * step
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
            }
        }
        .onChange(of: current) { _, new in
            let delta = ((new - shown) % n + n) % n
            shown = new
            withAnimation(reduceMotion ? nil : .spring(response: 1.0, dampingFraction: 0.85)) {
                rotation -= Double(delta) * step
            }
        }
    }
}

/// Growth rings: one per cycle (or week). Oldest in the middle, newest outside.
struct RingsView: View {
    var rings: [Engine.Ring]
    var size: CGFloat = 250

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let inner = sz.width * 0.12
            let outer = sz.width / 2 - 6
            let count = max(rings.count, 6)
            let gap = (outer - inner) / CGFloat(count)
            let sw = max(2, min(7, gap * 0.62))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - inner * 0.55, y: c.y - inner * 0.55, width: inner * 1.1, height: inner * 1.1)), with: .color(Palette.surface2))
            for (ri, ring) in rings.enumerated() {
                let r = inner + gap * (CGFloat(ri) + 0.5)
                let segs = ring.segments.count
                let full = max(segs, segs < 4 ? 7 : segs)
                let segAngle = 2 * Double.pi / Double(full)
                let pad = min(0.12, segAngle * 0.18)
                for (si, sg) in ring.segments.enumerated() {
                    let a0 = -Double.pi / 2 + Double(si) * segAngle + pad / 2
                    let a1 = a0 + segAngle - pad
                    var p = Path()
                    p.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                    if sg.done {
                        ctx.stroke(p, with: .color(sg.hue.color), style: StrokeStyle(lineWidth: sw, lineCap: .round))
                    } else {
                        ctx.stroke(p, with: .color(Palette.line2), style: StrokeStyle(lineWidth: max(1, sw * 0.35), lineCap: .round))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(rings.count) rings, one per cycle")
    }
}

/// Countdown ring for the wait between steps.
struct TimerRingView: View {
    var total: TimeInterval
    var endsAt: Date
    var hue: Hue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, endsAt.timeIntervalSince(ctx.date))
            let frac = total > 0 ? left / total : 0
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(hue.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: frac)
                VStack(spacing: 6) {
                    Text(Self.format(left))
                        .font(Typeface.display(56, weight: 380))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("until the next step").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(width: 236, height: 236)
            .accessibilityElement()
            .accessibilityLabel("\(Int(left / 60)) minutes \(Int(left) % 60) seconds left")
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Seven days around today, with each night's hue: the look-ahead.
struct WeekStrip: View {
    var days: [(day: Day, inst: Instance?)]
    var today: Day
    var onTap: (Day) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.day) { item in
                let isToday = item.day == today
                Button {
                    onTap(item.day)
                } label: {
                    VStack(spacing: 6) {
                        Text(item.day.weekdayShort.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                        Text("\(item.day.day)")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                        dot(item.inst)
                    }
                    .foregroundStyle(isToday ? Palette.ink : Palette.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isToday {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Palette.surface)
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibility(item.day, item.inst))
            }
        }
    }

    @ViewBuilder
    private func dot(_ inst: Instance?) -> some View {
        if let inst, inst.status != .off {
            switch inst.status {
            case .done:
                Circle().fill(inst.hue.color).frame(width: 13, height: 13)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(Color(hex: 0x13201C)))
            case .future, .pending:
                Circle().strokeBorder(inst.hue.color, lineWidth: 2).frame(width: 13, height: 13)
                    .opacity(inst.rest == .pause ? 0.5 : 1)
            default:
                Circle().strokeBorder(Palette.line2, lineWidth: 1.5).frame(width: 13, height: 13)
            }
        } else {
            Color.clear.frame(width: 13, height: 13)
        }
    }

    private func accessibility(_ day: Day, _ inst: Instance?) -> String {
        guard let inst else { return day.long }
        let status: String
        switch inst.status {
        case .done: status = "done"
        case .skipped: status = "skipped"
        case .future, .pending: status = "planned"
        default: status = ""
        }
        return "\(day.long), \(inst.label), \(status)"
    }
}
