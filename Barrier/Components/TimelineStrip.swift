import BarrierCore
import SwiftUI

// The treatment timeline: one column per day. Rows show each routine (a full
// clay bar = done with actives, a short light bar = basics only, an outline =
// missed), skin check-ins, the weekly overall score, and the events that
// explain the rest: breaks, procedures, routine changes and photos.
//
// One hue (clay) carries use; shape and fill tell the states apart, so it reads
// in grayscale and for color-blind readers. Red appears only for irritation,
// on its own row. Drawn with plain shapes so it renders into the PDF report.

struct TimelineColors {
    var accent: Color
    var ink: Color
    var ink2: Color
    var ink3: Color
    var line: Color
    var danger: Color
    var band: Color
    var surface: Color

    static let app = TimelineColors(accent: Palette.hueInk(.clay), ink: Palette.ink, ink2: Palette.ink2, ink3: Palette.ink3,
                                    line: Palette.line2, danger: Palette.danger, band: Palette.hueInk(.mist).opacity(0.13),
                                    surface: Palette.surface)
    static let paper = TimelineColors(accent: Color(hex: 0xA6512E), ink: Color(hex: 0x1B2A26), ink2: Color(hex: 0x485853),
                                      ink3: Color(hex: 0x6B7772), line: Color(hex: 0x1B2A26, alpha: 0.22), danger: Color(hex: 0xA4402F),
                                      band: Color(hex: 0x47707C, alpha: 0.12), surface: .white)
}

struct TimelineStrip: View {
    var data: TreatmentTimeline
    var width: CGFloat
    var colors: TimelineColors = .app
    /// Small type for the PDF.
    var compact = false

    private var labelW: CGFloat { compact ? 50 : 58 }
    private var font: CGFloat { compact ? 7.5 : 10 }
    private var dayW: CGFloat { (width - labelW) / CGFloat(max(1, data.days)) }
    private let rowH: CGFloat = 10
    private let rowGap: CGFloat = 5

    // Lanes, top to bottom.
    private var topH: CGFloat { compact ? 11 : 14 }
    private var rowsTop: CGFloat { topH + 2 }
    private var skinY: CGFloat { rowsTop + CGFloat(data.rows.count) * (rowH + rowGap) + 4 }
    private var scoreTop: CGFloat { skinY + 9 }
    private var scoreH: CGFloat { data.scores.isEmpty ? 0 : 26 }
    private var procY: CGFloat { scoreTop + scoreH + (data.scores.isEmpty ? 0 : 8) + 2 }
    private var eventY: CGFloat { procY + 16 }
    private var axisY: CGFloat { eventY + 14 }
    var height: CGFloat { axisY + (compact ? 10 : 13) }

    private func x(_ i: Int) -> CGFloat { labelW + (CGFloat(i) + 0.5) * dayW }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bands
            cells
            skin
            if !data.scores.isEmpty { score }
            events
            axis
            labels
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    // MARK: Breaks

    private var bands: some View {
        let rects = data.breaks.map { b in
            CGRect(x: x(b.from) - dayW / 2, y: rowsTop - 3, width: CGFloat(b.to - b.from + 1) * dayW, height: eventY + 6 - (rowsTop - 3))
        }
        return ZStack(alignment: .topLeading) {
            Boxes(rects: rects, corner: 3).fill(colors.band)
            ForEach(Array(data.breaks.enumerated()), id: \.offset) { _, b in
                leading(b.label, x: x(b.from) - dayW / 2, y: topH / 2, color: colors.ink3, maxWidth: max(40, CGFloat(b.to - b.from + 1) * dayW + 60))
            }
        }
    }

    // MARK: Routine rows

    private var cells: some View {
        var activeDone: [CGRect] = []
        var basicsDone: [CGRect] = []
        var activeMissed: [CGRect] = []
        var basicsMissed: [CGRect] = []
        var pending: [CGRect] = []
        let cw = max(1.5, dayW * (dayW > 6 ? 0.68 : 0.8))
        for (r, row) in data.rows.enumerated() {
            let top = rowsTop + CGFloat(r) * (rowH + rowGap)
            for (i, m) in row.marks.enumerated() {
                let full = CGRect(x: x(i) - cw / 2, y: top, width: cw, height: rowH)
                let short = CGRect(x: x(i) - cw / 2, y: top + rowH * 0.3, width: cw, height: rowH * 0.4)
                switch m {
                case .none: break
                case .activeDone: activeDone.append(full)
                case .basicsDone: basicsDone.append(short)
                case .activeMissed: activeMissed.append(full.insetBy(dx: 0.4, dy: 0.4))
                case .basicsMissed: basicsMissed.append(short.insetBy(dx: 0.4, dy: 0.4))
                case .pending: pending.append(full.insetBy(dx: 0.4, dy: 0.4))
                }
            }
        }
        let corner = min(2, cw / 2)
        return ZStack(alignment: .topLeading) {
            Boxes(rects: activeDone, corner: corner).fill(colors.accent)
            Boxes(rects: basicsDone, corner: corner).fill(colors.accent.opacity(0.4))
            Boxes(rects: activeMissed, corner: corner).stroke(colors.accent, lineWidth: 0.9)
            Boxes(rects: basicsMissed, corner: corner).stroke(colors.ink3, lineWidth: 0.8)
            Boxes(rects: pending, corner: corner).stroke(colors.ink3, style: StrokeStyle(lineWidth: 0.9, dash: [1.5, 1.5]))
        }
    }

    // MARK: Skin

    private var skin: some View {
        let r: CGFloat = min(3.2, max(1.6, dayW * 0.32))
        func dot(_ i: Int, _ scale: CGFloat) -> CGRect {
            CGRect(x: x(i) - r * scale, y: skinY - r * scale, width: 2 * r * scale, height: 2 * r * scale)
        }
        let irritated = data.skin.filter { $0.value == .irritated }.map { dot($0.key, 1) }
        let symptoms = data.skin.filter { $0.value == .symptoms }.map { dot($0.key, 0.8) }
        let calm = data.skin.filter { $0.value == .calm }.map { dot($0.key, 0.8) }
        return ZStack(alignment: .topLeading) {
            Dots(rects: calm).stroke(colors.ink3, lineWidth: 0.8)
            Dots(rects: symptoms).fill(colors.ink3)
            Dots(rects: irritated).fill(colors.danger)
        }
    }

    // MARK: Overall score

    private func scoreY(_ v: Int) -> CGFloat { scoreTop + scoreH * (1 - CGFloat(v - 1) / 4) }

    private var score: some View {
        let points = data.scores.map { CGPoint(x: x($0.day), y: scoreY($0.value)) }
        let guides = [scoreY(5), scoreY(3), scoreY(1)].map { y in [CGPoint(x: labelW, y: y), CGPoint(x: width, y: y)] }
        let first = data.scores.first!
        let last = data.scores.last!
        return ZStack(alignment: .topLeading) {
            ForEach(0..<guides.count, id: \.self) { g in
                Line(points: guides[g]).stroke(colors.line.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
            Line(points: points).stroke(colors.ink2, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            Dots(rects: points.map { CGRect(x: $0.x - 2.6, y: $0.y - 2.6, width: 5.2, height: 5.2) }).fill(colors.ink)
            // Direct labels on the first and the latest only.
            leading(Scores.label(first.value), x: x(first.day) + 5, y: scoreY(first.value) - 7, color: colors.ink3, maxWidth: 80)
            if data.scores.count > 1 {
                trailing(Scores.label(last.value), x: x(last.day) - 5, y: scoreY(last.value) - 7, color: colors.ink2, maxWidth: 80)
            }
        }
    }

    // MARK: Events

    private var events: some View {
        let d: CGFloat = 4
        let diamonds = data.procedures.map { CGPoint(x: x($0.day), y: procY) }
        let photos = data.photos.map { CGRect(x: x($0) - 2.6, y: eventY - 2.6, width: 5.2, height: 5.2) }
        // Procedure names, skipping ones that would run into the previous label.
        var named: [(Int, String)] = []
        var lastEnd: CGFloat = -100
        for p in data.procedures where x(p.day) > lastEnd {
            named.append((p.day, p.name))
            lastEnd = x(p.day) + CGFloat(p.name.count) * font * 0.55 + 14
        }
        return ZStack(alignment: .topLeading) {
            Diamonds(centers: diamonds, size: d).fill(colors.accent)
            ForEach(Array(named.enumerated()), id: \.offset) { _, n in
                if x(n.0) > width - 70 {
                    trailing(n.1, x: x(n.0) - d - 3, y: procY, color: colors.ink2, maxWidth: 120)
                } else {
                    leading(n.1, x: x(n.0) + d + 3, y: procY, color: colors.ink2, maxWidth: 120)
                }
            }
            Boxes(rects: photos, corner: 1).stroke(colors.ink2, lineWidth: 0.9)
            ForEach(Array(data.changes.enumerated()), id: \.offset) { _, c in
                ZStack {
                    Circle().fill(colors.ink)
                    Text("\(c.number)").font(.system(size: compact ? 6.5 : 8, weight: .bold)).foregroundStyle(colors.surface)
                }
                .frame(width: compact ? 10 : 12, height: compact ? 10 : 12)
                .position(x: x(c.day), y: eventY)
            }
        }
    }

    // MARK: Axis and row labels

    private var axis: some View {
        var ticks: [(Int, String)] = []
        for i in 0..<data.days {
            let day = data.from.adding(i)
            if day.day == 1 || i == 0 { ticks.append((i, day.date().formatted(.dateTime.month(.abbreviated)))) }
        }
        // The first label only if the month's first day isn't right after it.
        if ticks.count > 1, CGFloat(ticks[1].0 - ticks[0].0) * dayW < 26 { ticks.removeFirst() }
        let lines = ticks.map { [CGPoint(x: x($0.0) - dayW / 2, y: axisY - 4), CGPoint(x: x($0.0) - dayW / 2, y: axisY)] }
        return ZStack(alignment: .topLeading) {
            Line(points: [CGPoint(x: labelW, y: axisY - 4), CGPoint(x: width, y: axisY - 4)]).stroke(colors.line, lineWidth: 0.6)
            ForEach(0..<lines.count, id: \.self) { l in Line(points: lines[l]).stroke(colors.line, lineWidth: 0.6) }
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                if x(t.0) < width - 40 {
                    leading(t.1, x: x(t.0) - dayW / 2 + 2, y: axisY + 4, color: colors.ink3, maxWidth: 40)
                }
            }
            trailing("Today", x: width, y: axisY + 4, color: colors.ink3, maxWidth: 40)
        }
    }

    private var labels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(data.rows.enumerated()), id: \.offset) { r, row in
                leading(row.name, x: 0, y: rowsTop + CGFloat(r) * (rowH + rowGap) + rowH / 2, color: colors.ink2, maxWidth: labelW - 4)
            }
            leading("Skin", x: 0, y: skinY, color: colors.ink2, maxWidth: labelW - 4)
            if !data.scores.isEmpty {
                leading("Overall", x: 0, y: scoreTop + scoreH / 2, color: colors.ink2, maxWidth: labelW - 4)
            }
            leading("Events", x: 0, y: (procY + eventY) / 2, color: colors.ink2, maxWidth: labelW - 4)
        }
    }

    private func leading(_ s: String, x: CGFloat, y: CGFloat, color: Color, maxWidth: CGFloat) -> some View {
        Text(s).font(.system(size: font, weight: .medium)).foregroundStyle(color).lineLimit(1)
            .frame(width: maxWidth, alignment: .leading)
            .position(x: x + maxWidth / 2, y: y)
    }

    private func trailing(_ s: String, x: CGFloat, y: CGFloat, color: Color, maxWidth: CGFloat) -> some View {
        Text(s).font(.system(size: font, weight: .medium)).foregroundStyle(color).lineLimit(1)
            .frame(width: maxWidth, alignment: .trailing)
            .position(x: x - maxWidth / 2, y: y)
    }

    private var summary: String {
        var parts: [String] = ["Timeline, \(data.from.long) to today"]
        for row in data.rows {
            let c = data.counts(row.slot)
            parts.append("\(row.name): \(c.done) of \(c.due) done")
        }
        let irritated = data.skin.values.filter { $0 == .irritated }.count
        if irritated > 0 { parts.append("\(irritated) irritated day\(irritated == 1 ? "" : "s")") }
        if let first = data.scores.first, let last = data.scores.last, data.scores.count > 1 {
            parts.append("overall skin \(Scores.label(first.value)) to \(Scores.label(last.value))")
        }
        if !data.procedures.isEmpty { parts.append(data.procedures.map(\.name).joined(separator: ", ")) }
        if !data.changes.isEmpty { parts.append("\(data.changes.count) routine change\(data.changes.count == 1 ? "" : "s")") }
        return parts.joined(separator: ". ")
    }
}

/// What the marks mean.
struct TimelineLegend: View {
    var colors: TimelineColors = .app
    var compact = false

    var body: some View {
        let size: CGFloat = compact ? 7.5 : 11
        FlowLayout(spacing: compact ? 10 : 12) {
            item("With actives", size) { RoundedRectangle(cornerRadius: 1.5).fill(colors.accent).frame(width: 5, height: 10) }
            item("Basics only", size) { RoundedRectangle(cornerRadius: 1.5).fill(colors.accent.opacity(0.4)).frame(width: 5, height: 4) }
            item("Missed", size) { RoundedRectangle(cornerRadius: 1.5).stroke(colors.accent, lineWidth: 0.9).frame(width: 5, height: 10) }
            item("Irritated skin", size) { Circle().fill(colors.danger).frame(width: 6, height: 6) }
            item("Procedure", size) { Diamonds(centers: [CGPoint(x: 4, y: 4)], size: 4).fill(colors.accent).frame(width: 8, height: 8) }
            item("Routine change", size) { Circle().fill(colors.ink).frame(width: 8, height: 8) }
            item("Photo", size) { RoundedRectangle(cornerRadius: 1).stroke(colors.ink2, lineWidth: 0.9).frame(width: 6, height: 6) }
            item("Break", size) { RoundedRectangle(cornerRadius: 2).fill(colors.band).frame(width: 12, height: 8) }
        }
    }

    private func item<S: View>(_ text: String, _ size: CGFloat, @ViewBuilder _ swatch: () -> S) -> some View {
        HStack(spacing: 4) {
            swatch()
            Text(text).font(.system(size: size)).foregroundStyle(colors.ink3)
        }
    }
}

// MARK: - Shapes (plain paths render into the PDF)

struct Boxes: Shape {
    var rects: [CGRect]
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in rects { p.addRoundedRect(in: r, cornerSize: CGSize(width: corner, height: corner)) }
        return p
    }
}

struct Dots: Shape {
    var rects: [CGRect]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in rects { p.addEllipse(in: r) }
        return p
    }
}

struct Line: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }
}

struct Diamonds: Shape {
    var centers: [CGPoint]
    var size: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for c in centers {
            p.move(to: CGPoint(x: c.x, y: c.y - size))
            p.addLine(to: CGPoint(x: c.x + size, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + size))
            p.addLine(to: CGPoint(x: c.x - size, y: c.y))
            p.closeSubpath()
        }
        return p
    }
}
