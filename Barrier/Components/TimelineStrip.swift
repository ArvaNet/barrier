import BarrierCore
import SwiftUI

// The treatment timeline: one column per day. Rows show each routine (a tall
// clay bar = done with treatment, a short light bar = basics only, an outline =
// skipped or not logged), skin check-ins (face, and back when there is one), the
// weekly overall rating, and the events that explain the rest: breaks,
// procedures, photos and numbered routine changes.
//
// One hue (clay) carries use; shape and fill tell the states apart, so it reads
// in grayscale and for color-blind readers. Irritation is a red triangle on the
// skin rows. Drawn with plain shapes so it renders into the PDF report.

struct TimelineColors {
    var accent: Color
    var ink: Color
    var ink2: Color
    var ink3: Color
    var line: Color
    var danger: Color
    var band: Color
    var before: Color
    var surface: Color

    static let app = TimelineColors(accent: Palette.hueInk(.clay), ink: Palette.ink, ink2: Palette.ink2, ink3: Palette.ink3,
                                    line: Palette.line2, danger: Palette.danger, band: Palette.hueInk(.mist).opacity(0.14),
                                    before: Palette.ink.opacity(0.04), surface: Palette.surface)
    static let paper = TimelineColors(accent: Color(hex: 0xA6512E), ink: Color(hex: 0x1B2A26), ink2: Color(hex: 0x485853),
                                      ink3: Color(hex: 0x6B7772), line: Color(hex: 0x1B2A26, alpha: 0.22), danger: Color(hex: 0xA4402F),
                                      band: Color(hex: 0x47707C, alpha: 0.13), before: Color(hex: 0x1B2A26, alpha: 0.04), surface: .white)
}

struct TimelineStrip: View {
    var data: TreatmentTimeline
    var width: CGFloat
    var colors: TimelineColors = .app
    /// Small type for the PDF (and no "today, not done yet" mark: paper is read later).
    var compact = false

    private var labelW: CGFloat { compact ? 52 : 62 }
    private var font: CGFloat { compact ? 8 : 10 }
    private var dayW: CGFloat { (width - labelW) / CGFloat(max(1, data.days)) }
    private let rowH: CGFloat = 10
    private let rowGap: CGFloat = 5
    private let skinGap: CGFloat = 11

    // Lanes, top to bottom.
    private var topH: CGFloat { compact ? 11 : 14 }
    private var rowsTop: CGFloat { topH + 2 }
    private func rowTop(_ r: Int) -> CGFloat { rowsTop + CGFloat(r) * (rowH + rowGap) }
    private var skinY: CGFloat { rowTop(data.rows.count) + 3 }
    private var bodySkinY: CGFloat { skinY + (data.showsBodySkin ? skinGap : 0) }
    private var scoreTop: CGFloat { bodySkinY + 10 }
    private var scoreH: CGFloat { data.scores.isEmpty ? 0 : 26 }
    private var procY: CGFloat { scoreTop + scoreH + (data.scores.isEmpty ? 0 : 9) + 2 }
    private var eventY: CGFloat { procY + 15 }
    private var axisY: CGFloat { eventY + 15 }
    var height: CGFloat { axisY + (compact ? 10 : 13) }

    private func x(_ i: Int) -> CGFloat { labelW + (CGFloat(i) + 0.5) * dayW }

    var body: some View {
        ZStack(alignment: .topLeading) {
            before
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

    // MARK: Before the routine began

    @ViewBuilder
    private var before: some View {
        if data.beforeDays > 0 {
            let w = CGFloat(data.beforeDays) * dayW
            ZStack(alignment: .topLeading) {
                Boxes(rects: [CGRect(x: labelW, y: rowsTop - 3, width: w, height: eventY + 6 - (rowsTop - 3))], corner: 3).fill(colors.before)
                if w > textWidth("Before Tendwell") + 4 {
                    leading("Before Tendwell", x: labelW + 3, y: topH / 2, color: colors.ink3, maxWidth: w)
                }
            }
        }
    }

    // MARK: Breaks

    /// Rows a break covers: a face break leaves the body routine's row clear, and the other way round.
    private func rowsFor(_ area: Area?) -> [Int] {
        data.rows.indices.filter { r in area == nil || data.rows[r].slot.area == area }
    }

    private func bandLabel(_ b: TreatmentTimeline.Band) -> String {
        guard let area = b.area, data.rows.contains(where: { $0.slot == .body }) else { return b.label }
        return "\(b.label) (\(area == .face ? "face" : data.bodyName))"
    }

    private var bands: some View {
        var rects: [CGRect] = []
        for b in data.breaks {
            let x0 = x(b.from) - dayW / 2
            let w = CGFloat(b.to - b.from + 1) * dayW
            for r in rowsFor(b.area) {
                rects.append(CGRect(x: x0, y: rowTop(r) - 2.5, width: w, height: rowH + 5))
            }
            // The skin and event lanes below, always.
            rects.append(CGRect(x: x0, y: skinY - 6, width: w, height: eventY + 6 - (skinY - 6)))
        }
        return ZStack(alignment: .topLeading) {
            Boxes(rects: rects, corner: 2).fill(colors.band)
            ForEach(Array(data.breaks.enumerated()), id: \.offset) { _, b in
                // Starts with the band; kept inside the chart when the band is near the end.
                let label = bandLabel(b)
                let w = textWidth(label) + 4
                leading(label, x: min(x(b.from) - dayW / 2, width - w), y: topH / 2, color: colors.ink3, maxWidth: w)
            }
        }
    }

    // MARK: Routine rows

    private var cells: some View {
        var treated: [CGRect] = []
        var basics: [CGRect] = []
        var missed: [CGRect] = []
        var pending: [CGRect] = []
        // A column, but never a block: past about 6 pt a bar stops reading as a day.
        let cw = min(6, max(1.5, dayW * (dayW > 6 ? 0.68 : 0.8)))
        for (r, row) in data.rows.enumerated() {
            let top = rowTop(r)
            for (i, m) in row.marks.enumerated() {
                let full = CGRect(x: x(i) - cw / 2, y: top, width: cw, height: rowH)
                let short = CGRect(x: x(i) - cw / 2, y: top + rowH * 0.3, width: cw, height: rowH * 0.4)
                switch m {
                case .none: break
                case .activeDone: treated.append(full)
                case .basicsDone: basics.append(short)
                case .activeMissed, .basicsMissed: missed.append(full.insetBy(dx: 0.45, dy: 0.45))
                case .pending: if !compact { pending.append(full.insetBy(dx: 0.45, dy: 0.45)) }
                }
            }
        }
        let corner = min(2, cw / 2)
        return ZStack(alignment: .topLeading) {
            Boxes(rects: treated, corner: corner).fill(colors.accent)
            Boxes(rects: basics, corner: corner).fill(colors.accent.opacity(0.4))
            Boxes(rects: missed, corner: corner).stroke(colors.accent, lineWidth: 0.9)
            Boxes(rects: pending, corner: corner).stroke(colors.ink3, style: StrokeStyle(lineWidth: 0.9, dash: [1.5, 1.5]))
        }
    }

    // MARK: Skin

    private var skin: some View {
        let r: CGFloat = min(3.2, max(1.8, dayW * 0.32))
        var calm: [CGRect] = []
        var symptoms: [CGRect] = []
        var irritated: [CGPoint] = []
        func add(_ marks: [Int: TreatmentTimeline.Skin], y: CGFloat) {
            for (i, level) in marks {
                switch level {
                case .calm: calm.append(CGRect(x: x(i) - r * 0.85, y: y - r * 0.85, width: 1.7 * r, height: 1.7 * r))
                case .symptoms: symptoms.append(CGRect(x: x(i) - r * 0.85, y: y - r * 0.85, width: 1.7 * r, height: 1.7 * r))
                case .irritated: irritated.append(CGPoint(x: x(i), y: y))
                }
            }
        }
        add(data.skin, y: skinY)
        if data.showsBodySkin { add(data.bodySkin, y: bodySkinY) }
        return ZStack(alignment: .topLeading) {
            Dots(rects: calm).stroke(colors.ink3, lineWidth: 0.8)
            Dots(rects: symptoms).fill(colors.ink3)
            Triangles(centers: irritated, size: r * 1.25).fill(colors.danger)
        }
    }

    // MARK: Overall rating

    private func scoreY(_ v: Int) -> CGFloat { scoreTop + scoreH * (1 - CGFloat(v - 1) / 4) }

    private var score: some View {
        let points = data.scores.map { CGPoint(x: x($0.day), y: scoreY($0.value)) }
        let guides = [scoreY(5), scoreY(3), scoreY(1)].map { y in [CGPoint(x: labelW, y: y), CGPoint(x: width, y: y)] }
        let first = data.scores.first!
        let last = data.scores.last!
        let firstW = textWidth(Scores.label(first.value))
        let lastW = textWidth(Scores.label(last.value))
        // The first label only when it can't run into the last.
        let showFirst = data.scores.count == 1 || x(last.day) - x(first.day) >= 90
        return ZStack(alignment: .topLeading) {
            ForEach(0..<guides.count, id: \.self) { g in
                Line(points: guides[g]).stroke(colors.line.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
            Line(points: points).stroke(colors.ink2, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            Dots(rects: points.map { CGRect(x: $0.x - 2.6, y: $0.y - 2.6, width: 5.2, height: 5.2) }).fill(colors.ink)
            // Direct labels beside the points, clear of the line.
            if showFirst {
                if x(first.day) - firstW - 6 > labelW {
                    trailing(Scores.label(first.value), x: x(first.day) - 5, y: scoreY(first.value), color: colors.ink3, maxWidth: firstW + 4)
                } else {
                    leading(Scores.label(first.value), x: x(first.day) - 2, y: scoreY(first.value) + 8, color: colors.ink3, maxWidth: firstW + 4)
                }
            }
            if data.scores.count > 1 {
                if x(last.day) + lastW + 6 < width {
                    leading(Scores.label(last.value), x: x(last.day) + 5, y: scoreY(last.value), color: colors.ink2, maxWidth: lastW + 4)
                } else {
                    trailing(Scores.label(last.value), x: x(last.day) + 2, y: scoreY(last.value) - 8, color: colors.ink2, maxWidth: lastW + 4)
                }
            }
        }
    }

    // MARK: Events

    private var events: some View {
        let d: CGFloat = 4
        let diamonds = data.procedures.map { CGPoint(x: x($0.day), y: procY) }
        var named: [(Int, String)] = []
        var spans: [ClosedRange<CGFloat>] = []
        var lastEnd: CGFloat = -100
        for p in data.procedures where x(p.day) > lastEnd {
            named.append((p.day, p.name))
            let px = x(p.day)
            let w = textWidth(p.name) + 8
            // Where the label will sit (to the right, or to the left near the end).
            spans.append(px + w + d > width ? (px - d - w)...(px + d) : (px - d)...(px + d + w))
            lastEnd = px + textWidth(p.name) + 14
        }
        // Photos share the procedure lane, but never under a label: those drop to the change lane.
        let photos = data.photos.map { i -> CGRect in
            let px = x(i)
            let y = spans.contains { $0.contains(px) } ? eventY : procY
            return CGRect(x: px - 2.6, y: y - 2.6, width: 5.2, height: 5.2)
        }
        // Change markers too close to the one before drop half a lane, so both numbers read.
        let size: CGFloat = compact ? 10 : 12
        var markers: [(x: CGFloat, y: CGFloat, n: Int)] = []
        var prevX: CGFloat = -100
        var low = false
        for c in data.changes {
            let cx = x(c.day)
            low = cx - prevX < size + 1 ? !low : false
            markers.append((cx, eventY + (low ? 5 : 0), c.number))
            prevX = cx
        }
        return ZStack(alignment: .topLeading) {
            Boxes(rects: photos, corner: 1).stroke(colors.ink2, lineWidth: 0.9)
            Diamonds(centers: diamonds, size: d).fill(colors.accent)
            ForEach(Array(named.enumerated()), id: \.offset) { _, n in
                if x(n.0) + textWidth(n.1) + 8 > width {
                    trailing(n.1, x: x(n.0) - d - 3, y: procY, color: colors.ink2, maxWidth: textWidth(n.1) + 4)
                } else {
                    leading(n.1, x: x(n.0) + d + 3, y: procY, color: colors.ink2, maxWidth: textWidth(n.1) + 4)
                }
            }
            ForEach(Array(markers.enumerated()), id: \.offset) { _, m in
                ZStack {
                    Circle().fill(colors.ink)
                    Text("\(m.n)").font(.system(size: compact ? 6.5 : 8, weight: .bold)).foregroundStyle(colors.surface)
                }
                .frame(width: size, height: size)
                .position(x: m.x, y: m.y)
            }
        }
    }

    // MARK: Axis and row labels

    private var axis: some View {
        var ticks: [(Int, String)] = []
        for i in 0..<data.days {
            let day = data.from.adding(i)
            if day.day == 1 || i == 0 { ticks.append((i, day.date().formatted(.dateTime.month(.abbreviated).day()))) }
        }
        if ticks.count > 1, CGFloat(ticks[1].0 - ticks[0].0) * dayW < 34 { ticks.removeFirst() }
        let lines = ticks.map { [CGPoint(x: x($0.0) - dayW / 2, y: axisY - 4), CGPoint(x: x($0.0) - dayW / 2, y: axisY)] }
        return ZStack(alignment: .topLeading) {
            Line(points: [CGPoint(x: labelW, y: axisY - 4), CGPoint(x: width, y: axisY - 4)]).stroke(colors.line, lineWidth: 0.6)
            ForEach(0..<lines.count, id: \.self) { l in Line(points: lines[l]).stroke(colors.line, lineWidth: 0.6) }
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                if x(t.0) < width - 50 {
                    leading(t.1, x: x(t.0) - dayW / 2 + 2, y: axisY + 4, color: colors.ink3, maxWidth: 44)
                }
            }
            trailing("Today", x: width, y: axisY + 4, color: colors.ink3, maxWidth: 40)
        }
    }

    private var labels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(data.rows.enumerated()), id: \.offset) { r, row in
                leading(row.name, x: 0, y: rowTop(r) + rowH / 2, color: colors.ink2, maxWidth: labelW - 4)
            }
            leading(data.showsBodySkin ? "Face skin" : "Skin", x: 0, y: skinY, color: colors.ink2, maxWidth: labelW - 4)
            if data.showsBodySkin {
                leading("\(data.bodyName) skin", x: 0, y: bodySkinY, color: colors.ink2, maxWidth: labelW - 4)
            }
            if !data.scores.isEmpty {
                leading("Overall 1–5", x: 0, y: scoreTop + scoreH / 2, color: colors.ink2, maxWidth: labelW - 4)
            }
            leading("Events", x: 0, y: (procY + eventY) / 2, color: colors.ink2, maxWidth: labelW - 4)
        }
    }

    /// A rough width for a label at this size (system font, medium).
    private func textWidth(_ s: String) -> CGFloat { CGFloat(s.count) * font * 0.6 + 2 }

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
        var parts: [String] = ["Timeline, \(data.from.long) to today, one column per day"]
        for row in data.rows {
            let c = data.counts(row.slot)
            parts.append("\(row.name): \(c.done) of \(c.due) done")
        }
        let irritated = data.skin.values.filter { $0 == .irritated }.count + data.bodySkin.values.filter { $0 == .irritated }.count
        if irritated > 0 { parts.append("irritation logged on \(irritated) day\(irritated == 1 ? "" : "s")") }
        if let first = data.scores.first, let last = data.scores.last, data.scores.count > 1 {
            parts.append("overall rating \(Scores.label(first.value)) to \(Scores.label(last.value))")
        }
        if !data.procedures.isEmpty { parts.append(data.procedures.map(\.name).joined(separator: ", ")) }
        if !data.changes.isEmpty { parts.append("\(data.changes.count) routine change\(data.changes.count == 1 ? "" : "s")") }
        return parts.joined(separator: ". ")
    }
}

/// What the marks mean, in lane order.
struct TimelineLegend: View {
    var colors: TimelineColors = .app
    var compact = false

    var body: some View {
        let size: CGFloat = compact ? 7.5 : 11
        FlowLayout(spacing: compact ? 9 : 12) {
            item("With treatment", size) { RoundedRectangle(cornerRadius: 1.5).fill(colors.accent).frame(width: 5, height: 10) }
            item("Basics only", size) { RoundedRectangle(cornerRadius: 1.5).fill(colors.accent.opacity(0.4)).frame(width: 5, height: 4) }
            item("Skipped or not logged", size) { RoundedRectangle(cornerRadius: 1.5).stroke(colors.accent, lineWidth: 0.9).frame(width: 5, height: 10) }
            item("Calm", size) { Circle().stroke(colors.ink3, lineWidth: 0.9).frame(width: 6, height: 6) }
            item("Other symptoms", size) { Circle().fill(colors.ink3).frame(width: 6, height: 6) }
            item("Irritation logged", size) { Triangles(centers: [CGPoint(x: 4, y: 4)], size: 4).fill(colors.danger).frame(width: 8, height: 8) }
            item("Overall: weekly rating, 1 Rough to 5 Great", size) {
                Line(points: [CGPoint(x: 0, y: 6), CGPoint(x: 10, y: 2)]).stroke(colors.ink2, lineWidth: 1.2).frame(width: 10, height: 8)
            }
            item("Procedure", size) { Diamonds(centers: [CGPoint(x: 4, y: 4)], size: 4).fill(colors.accent).frame(width: 8, height: 8) }
            item("Photo", size) { RoundedRectangle(cornerRadius: 1).stroke(colors.ink2, lineWidth: 0.9).frame(width: 6, height: 6) }
            item("Routine change (see list)", size) { Circle().fill(colors.ink).frame(width: 8, height: 8) }
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

/// Upward triangles: irritation, so it reads without color.
struct Triangles: Shape {
    var centers: [CGPoint]
    var size: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for c in centers {
            p.move(to: CGPoint(x: c.x, y: c.y - size))
            p.addLine(to: CGPoint(x: c.x + size, y: c.y + size * 0.8))
            p.addLine(to: CGPoint(x: c.x - size, y: c.y + size * 0.8))
            p.closeSubpath()
        }
        return p
    }
}
