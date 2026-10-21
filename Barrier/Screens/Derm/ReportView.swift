import BarrierCore
import PDFKit
import SwiftUI

/// The report for the dermatologist, as A4 PDF pages:
/// 1. At a glance: what's in use now, the timeline, how it went, what changed, questions.
/// 2. The routine, the skin log and every routine change.
/// 3. Procedures and photos (when there are any).
/// The preview is the PDF itself, so it can be zoomed and matches the shared file.
struct ReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Built from made-up demo data, to show what a report looks like.
    var sample = false
    @State private var pdfURL: URL?
    @State private var pageCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    PDFPreview(url: pdfURL, startPage: startPage)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Text(sample ? "Sample data, made up for illustration. Pinch to zoom." : "Logged by you in Barrier. Not a medical record. Pinch to zoom.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Palette.bg.opacity(0.94))
            }
            .navigationTitle(sample ? "Sample report" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .task { await render() }
        }
    }

    /// Screenshot hooks: `-screen report-routine` (page 2), `-screen report-photos` (last page).
    private var startPage: Int? {
        switch model.launch.screen {
        case "report-routine": return 1
        case "report-photos": return pageCount > 0 ? pageCount - 1 : nil
        default: return nil
        }
    }

    private func render() async {
        var state: AppState
        let store: PhotoStore
        if sample {
            state = Presets.demoState(today: model.today)
            // Made-up data shouldn't carry a real-sounding doctor's name.
            state.plan.followUp?.with = nil
            for i in state.procedures.indices { state.procedures[i].clinic = nil }
            store = PhotoStore(demo: true)
            // The stand-in photos are drawn once, off the main thread.
            let photos = state.photos
            await Task.detached(priority: .userInitiated) { DemoPhotos.ensure(photos, in: store) }.value
        } else {
            state = model.state
            store = model.photos
        }
        let data = ReportData(state: state, today: model.today, photos: store, sample: sample)
        var views: [AnyView] = [AnyView(ReportSummaryPage(data: data)), AnyView(ReportRoutinePage(data: data))]
        if !data.photos.isEmpty || !data.procedures.isEmpty { views.append(AnyView(ReportPhotosPage(data: data))) }
        let size = CGSize(width: 595, height: 842)
        let name = sample ? "Barrier sample report.pdf" : "Barrier report \(model.today.iso).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var box = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        for v in views {
            let r = ImageRenderer(content: v.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
            r.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        pageCount = views.count
        pdfURL = url
    }
}

/// The PDF, zoomable (pinch or double-tap).
struct PDFPreview: UIViewRepresentable {
    var url: URL
    var startPage: Int?

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.pageShadowsEnabled = true
        v.backgroundColor = UIColor(Palette.bg)
        v.document = PDFDocument(url: url)
        if let i = startPage, let page = v.document?.page(at: i) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { v.go(to: page) }
        }
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}
}

/// Everything the report shows, computed once.
struct ReportData {
    struct StepLine: Hashable { var name: String; var detail: String }

    var sample: Bool
    var today: Day
    var from: Day
    var followUp: FollowUp?
    var pmSteps: [StepLine]
    var amSteps: [StepLine]
    var rotation: String?
    var easing: String?
    var products: [Product]
    var byLabel: [(String, Int)]
    var recovery: Int
    /// "Paused Oct 1–Oct 4: traveling", "Actives break Oct 7–Oct 15: Subcision".
    var pauseLines: [String]
    /// Past ones (latest 4) and the next one booked, oldest first. Five at most, so page 3 never overflows.
    var procedures: [Procedure]
    /// "5 weeks after Subcision", by photo id.
    var photoContext: [String: String]
    var checkins: [CheckIn]
    var questions: [Question]
    var notes: String?
    var ifIrritated: String?
    var photos: [(PhotoMeta, UIImage)]
    /// The body routine ("Back"), when it's on.
    var bodyName: String?
    var bodyWhen: String?
    var bodySteps: [StepLine] = []
    /// The last up to 14 weeks, drawn on page 1.
    var timeline: TreatmentTimeline
    /// "Tretinoin 0.025% cream every night · Azelaic acid 15% every morning".
    var nowLine: String?
    /// "Not great (Sep 28) → Good (Oct 14)", per area.
    var scoreLines: [String] = []
    /// Every routine change, numbered from the start of the log.
    var allChanges: [PlanChange] = []
    /// When the change log starts (nil without one).
    var logStart: Day?

    @MainActor
    init(state s: AppState, today: Day, photos store: PhotoStore, sample: Bool = false) {
        self.sample = sample
        self.today = today
        from = s.plan.createdAt
        followUp = s.plan.followUp
        let products = Dictionary(s.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func lines(_ slot: Slot) -> [StepLine] {
            let sp = s.plan[slot]
            guard sp.enabled else { return [] }
            return sp.steps.compactMap { st in
                guard let p = products[st.productId] else { return nil }
                var d = [Engine.describe(st, in: sp, slot: slot)]
                if let a = st.amount { d.append(a) }
                if let w = st.waitMin, w > 0 { d.append("wait \(w) min after") }
                return StepLine(name: p.name, detail: d.joined(separator: " · "))
            }
        }
        pmSteps = lines(.pm)
        amSteps = lines(.am)
        let bp = s.plan.body
        let bodyOn = bp.enabled && !bp.steps.isEmpty
        if bodyOn {
            bodyName = bp.displayName
            bodyWhen = "\(bp.cue ?? "Daily"), around \(bp.time.formatted)."
            bodySteps = lines(.body)
        }
        rotation = s.plan.pm.length > 1 ? "Evening repeats every \(s.plan.pm.length) nights." : nil
        if let e = s.plan.pm.easeIn {
            let end = e.start.adding(e.totalDays)
            easing = end > today ? "Easing in since \(e.start.short), full routine from \(end.short)." : "Eased in from \(e.start.short) to \(end.short)."
        }
        let used = s.usedProductIDs
        self.products = s.products.filter { used.contains($0.id) && ($0.kind.isActive || $0.kind == .oral || $0.note != nil) }
        // What's in use now: treatments and medication, with how often.
        var now: [String] = []
        for slot in [Slot.pm, .am, .body] {
            let sp = s.plan[slot]
            guard sp.enabled else { continue }
            for st in sp.steps {
                guard let p = products[st.productId], p.kind.isActive || p.kind == .oral, !now.contains(where: { $0.hasPrefix(p.name + " ") }) else { continue }
                let place = slot == .body ? " (\(bp.displayName))" : ""
                now.append("\(p.name) \(PlanHistory.lowered(Engine.describe(st, in: sp, slot: slot)))\(place)")
            }
        }
        nowLine = now.isEmpty ? nil : now.joined(separator: " · ")
        let st = Engine.stats(s, today: today)
        byLabel = st.byLabel.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        recovery = st.recoveryNights
        pauseLines = s.pauses.filter { $0.from <= today }.sorted { $0.from < $1.from }.suffix(4).map { p in
            let span = p.from == p.to ? p.from.short : "\(p.from.short)–\(p.to.short)"
            if let id = p.procedureID, let proc = s.procedures.first(where: { $0.id == id }) {
                return "Actives break \(span): \(proc.name)"
            }
            return "Paused \(span): \(p.reason.label.lowercased())"
        }
        let past = Procedures.past(s, today: today.adding(1)).prefix(4).reversed()
        procedures = Array(past) + Procedures.upcoming(s, today: today.adding(1)).prefix(1)
        checkins = Array(s.checkins.sorted { $0.day > $1.day }.prefix(24))
        questions = s.questions.sorted { !$0.answered && $1.answered }
        notes = s.plan.dermNotes
        ifIrritated = s.plan.ifIrritated
        let span = TreatmentTimeline.build(s, today: today)
        timeline = span
        allChanges = PlanHistory.changes(s)
        logStart = s.history.first?.day
        for area in Scores.areas(s) {
            let list = s.scores.filter { $0.place == area && $0.day >= span.from }.sorted { $0.day < $1.day }
            guard let first = list.first else { continue }
            let name = area == .face ? "Face" : (bodyOn ? bp.displayName : "Body")
            if let last = list.last, list.count > 1 {
                scoreLines.append("\(name): \(Scores.label(first.value)) (\(first.day.short)) → \(Scores.label(last.value)) (\(last.day.short))")
            } else {
                scoreLines.append("\(name): \(Scores.label(first.value)) (\(first.day.short))")
            }
        }
        // Up to six: the latest procedure's before and after on each area, then per
        // area the first and the latest photo, then recent ones. Face first, then body.
        var pick: [PhotoMeta] = []
        func add(_ m: PhotoMeta?) {
            if let m, pick.count < 6, !pick.contains(m) { pick.append(m) }
        }
        for area in Area.allCases {
            if let p = Procedures.past(s, today: today.adding(1)).first(where: { $0.place == area }) {
                add(Procedures.beforePhoto(p, in: s))
                add(Procedures.afterPhoto(p, in: s))
            }
        }
        let byArea = Area.allCases.map { a in s.photos.filter { $0.place == a }.sorted { $0.at < $1.at } }.filter { !$0.isEmpty }
        for list in byArea {
            add(list.first)
            add(list.last)
        }
        for list in byArea {
            for p in list.reversed() { add(p) }
        }
        let ordered = pick.sorted { a, b in a.place == b.place ? a.at < b.at : a.place == .face }
        photos = ordered.compactMap { m in store.image(m.id).map { (m, $0) } }
        var context: [String: String] = [:]
        for m in ordered { context[m.id] = Procedures.context(m, in: s) }
        photoContext = context
    }

    var kicker: String { sample ? "BARRIER · SAMPLE REPORT" : "BARRIER · SKIN ROUTINE REPORT" }

    var footer: String {
        sample ? "Sample report with made-up data, for illustration. Not a real patient."
            : "Logged by the patient in Barrier on \(today.long). Not a medical record."
    }

    /// "the last 14 weeks" or "since Sep 28".
    var window: String {
        timeline.days >= 98 ? "the last 14 weeks" : "since \(timeline.from.short)"
    }

    /// What to say when the timeline has no routine changes.
    var noChangesLine: String {
        if let last = allChanges.last {
            return "No changes in \(window) (last: \(last.day.short))."
        }
        return logStart.map { "Changes noted from \($0.short). None since." } ?? "No changes logged."
    }
}

private enum Paper {
    static let ink = Color(hex: 0x1B2A26)
    static let ink2 = Color(hex: 0x485853)
    static let ink3 = Color(hex: 0x6B7772)
    static let line = Color(hex: 0x1B2A26, alpha: 0.14)
    static let accent = Color(hex: 0xA6512E)
    static let danger = Color(hex: 0xA4402F)

    static func block<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 8.5, weight: .bold)).tracking(1).foregroundStyle(ink3)
            content()
        }
    }

    static func steps(_ lines: [ReportData.StepLine]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(i + 1)").font(.system(size: 9).monospacedDigit()).foregroundStyle(ink3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.name).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                        Text(l.detail).font(.system(size: 9)).foregroundStyle(ink2).lineLimit(2)
                    }
                }
            }
        }
    }

    static func stat(_ big: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(big).font(.system(size: 13, weight: .semibold).monospacedDigit())
            Text(label).font(.system(size: 9.5)).foregroundStyle(ink2).lineLimit(1)
        }
    }

    /// One line at most, so the page can't overflow.
    static func line(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5)).foregroundStyle(ink2).lineLimit(1)
    }

    static func small(_ s: String, lines: Int = 3) -> some View {
        Text(s).font(.system(size: 9.5)).foregroundStyle(ink2).lineLimit(lines)
    }

    /// A numbered marker, matching the timeline's routine-change markers.
    static func number(_ n: Int) -> some View {
        ZStack {
            Circle().fill(ink)
            Text("\(n)").font(.system(size: 6.5, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 10, height: 10)
    }

    /// Changes, numbered, each line on one line.
    static func changes(_ list: [PlanChange]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(list, id: \.number) { c in
                HStack(alignment: .top, spacing: 6) {
                    number(c.number).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.day.short).font(.system(size: 9, weight: .semibold)).foregroundStyle(ink3)
                        ForEach(Array(c.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 9.5)).foregroundStyle(ink).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    /// The latest changes that fit `budget` lines, oldest first, and how many lines were left out.
    static func fit(_ list: [PlanChange], budget: Int) -> (shown: [PlanChange], left: Int) {
        var shown: [PlanChange] = []
        var used = 0
        for c in list.reversed() {
            if used + c.lines.count > budget {
                if shown.isEmpty {
                    var cut = c
                    cut.lines = Array(c.lines.prefix(budget))
                    shown.append(cut)
                    used = budget
                }
                break
            }
            shown.append(c)
            used += c.lines.count
        }
        let total = list.reduce(0) { $0 + $1.lines.count }
        return (shown.reversed(), total - used)
    }
}

/// A page frame: kicker, title, optional subtitle, content, and a footer nothing can push off.
private struct ReportPage<Content: View>: View {
    var kicker: String
    var title: String
    var subtitle: String?
    var footer: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Paper.accent)
                Text(title).font(Typeface.display(24, weight: 430))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Paper.ink2).lineLimit(2) }
                Rectangle().fill(Paper.line).frame(height: 1).padding(.top, 6)
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 56)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            Text(footer).font(.system(size: 8.5)).foregroundStyle(Paper.ink3)
                .frame(width: 523, alignment: .leading)
                .padding(.vertical, 6)
                .background(Color.white)
                .padding(.horizontal, 36)
                .padding(.bottom, 30)
        }
        .background(Color.white)
        .foregroundStyle(Paper.ink)
    }
}

// MARK: - Page 1: at a glance

struct ReportSummaryPage: View {
    var data: ReportData

    private var subtitle: String? {
        data.followUp.map { "For the visit on \($0.day.long)\($0.with.map { " with \($0)" } ?? "")" }
    }

    var body: some View {
        ReportPage(kicker: data.kicker, title: "\(data.from.short) – \(data.today.short)", subtitle: subtitle, footer: data.footer) {
            if let now = data.nowLine {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("NOW").font(.system(size: 8.5, weight: .bold)).tracking(1).foregroundStyle(Paper.accent)
                    Text(now).font(.system(size: 10, weight: .medium)).lineLimit(2)
                }
            }
            Paper.block("Timeline, \(data.window) · one column per day") {
                TimelineStrip(data: data.timeline, width: 523, colors: .paper, compact: true)
                TimelineLegend(colors: .paper, compact: true).padding(.top, 2)
                if !data.timeline.earlier.isEmpty {
                    Paper.line("Earlier: " + data.timeline.earlier.map { "\($0.name) (\($0.day.short))" }.joined(separator: ", ") + ". All procedures are on the last page.")
                }
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    howItWent
                    questions
                }
                .frame(width: 250, alignment: .leading)
                VStack(alignment: .leading, spacing: 14) {
                    changes
                    if data.notes != nil || data.ifIrritated != nil {
                        Paper.block("Instructions noted") {
                            if let a = data.notes { Paper.small(a, lines: 3) }
                            if let b = data.ifIrritated { Paper.small("If irritated: \(b)", lines: 3) }
                        }
                    }
                }
            }
        }
    }

    private var howItWent: some View {
        Paper.block("How it went, \(data.window)") {
            // The same numbers the timeline draws: done of due, per routine.
            ForEach(data.timeline.rows, id: \.slot) { row in
                let c = data.timeline.counts(row.slot)
                let unit = row.slot == .pm ? "evenings" : row.slot == .am ? "mornings" : "\(row.name) days"
                if c.due > 0 { Paper.stat("\(c.done) of \(c.due)", "\(unit) done") }
            }
            if data.recovery > 0 { Paper.stat("\(data.recovery)", "recovery nights for irritation") }
            if !data.scoreLines.isEmpty {
                Text("Overall skin, rated weekly by the patient").font(.system(size: 9.5, weight: .semibold)).padding(.top, 3)
                ForEach(data.scoreLines, id: \.self) { Paper.line($0) }
            }
            ForEach(data.pauseLines, id: \.self) { Paper.line($0) }
        }
    }

    @ViewBuilder
    private var questions: some View {
        if !data.questions.isEmpty {
            let shown = Array(data.questions.prefix(6))
            Paper.block("Questions") {
                ForEach(shown, id: \.id) { q in
                    HStack(alignment: .top, spacing: 6) {
                        Text(q.answered ? "✓" : "•").font(.system(size: 10, weight: .bold)).foregroundStyle(Paper.accent)
                        Text(q.text).font(.system(size: 10.5)).foregroundStyle(q.answered ? Paper.ink3 : Paper.ink).lineLimit(3)
                    }
                }
                if data.questions.count > shown.count {
                    Paper.line("+\(data.questions.count - shown.count) more in the app")
                }
            }
        }
    }

    private var changes: some View {
        let inRange = data.timeline.changes.map(\.change)
        let fit = Paper.fit(inRange, budget: 10)
        return Paper.block("Routine changes") {
            if inRange.isEmpty { Paper.small(data.noChangesLine) }
            Paper.changes(fit.shown)
            if fit.left > 0 || data.allChanges.count > inRange.count {
                Paper.line("Earlier changes in full on page 2.")
            }
        }
    }
}

// MARK: - Page 2: routine, skin log, every change

struct ReportRoutinePage: View {
    var data: ReportData

    var body: some View {
        // The skin log makes room for the change list.
        let fit = Paper.fit(data.allChanges, budget: 22)
        let logRows = data.allChanges.isEmpty ? 24 : 12
        ReportPage(kicker: data.kicker, title: "Routine and skin log", subtitle: "As of \(data.today.long)", footer: data.footer) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    if !data.pmSteps.isEmpty {
                        Paper.block("Evening routine") {
                            if let r = data.rotation { Paper.line(r) }
                            if let e = data.easing { Paper.line(e) }
                            Paper.steps(data.pmSteps)
                        }
                    }
                    if !data.amSteps.isEmpty {
                        Paper.block("Morning routine") { Paper.steps(data.amSteps) }
                    }
                    if let name = data.bodyName {
                        Paper.block("\(name) routine") {
                            if let w = data.bodyWhen { Paper.line(w) }
                            Paper.steps(data.bodySteps)
                        }
                    }
                    if !data.products.isEmpty {
                        Paper.block("Treatments") {
                            ForEach(data.products.prefix(8), id: \.id) { p in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                    Text([p.from.map { "since \($0.short)" }, p.until.map { "until \($0.short)" }, p.note].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 9.5)).foregroundStyle(Paper.ink2).lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .frame(width: 250, alignment: .leading)
                VStack(alignment: .leading, spacing: 14) {
                    Paper.block("Skin log") {
                        if data.checkins.isEmpty { Paper.small("No check-ins yet.") }
                        if !data.byLabel.isEmpty {
                            Paper.line(data.byLabel.map { "\($0.0): \($0.1)" }.joined(separator: " · ")).padding(.bottom, 4)
                        }
                        ForEach(data.checkins.prefix(logRows), id: \.self) { c in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(c.day.short).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Paper.ink3).frame(width: 40, alignment: .leading)
                                Text((c.place == .body ? "\(data.bodyName ?? "Body"): " : "") + ([c.feel.map(\.label).joined(separator: ", ")] + [c.note].compactMap { $0 }).joined(separator: ": "))
                                    .font(.system(size: 9.5, weight: c.feel.contains(where: \.isIrritation) ? .semibold : .regular))
                                    .foregroundStyle(c.feel.contains(where: \.isIrritation) ? Paper.danger : Paper.ink)
                                    .lineLimit(2)
                            }
                        }
                    }
                    if !data.allChanges.isEmpty {
                        Paper.block("Every routine change") {
                            Paper.changes(fit.shown)
                            if fit.left > 0 { Paper.line("+\(fit.left) older lines, in the app.") }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Page 3: procedures and photos

struct ReportPhotosPage: View {
    var data: ReportData

    private var hasProcedures: Bool { !data.procedures.isEmpty }
    /// Smaller photos when the procedures list shares the page.
    private var photoSize: CGSize { hasProcedures ? CGSize(width: 135, height: 180) : CGSize(width: 166, height: 221) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(data.sample ? data.kicker : hasProcedures ? "BARRIER · PROCEDURES AND PHOTOS" : "BARRIER · PROGRESS PHOTOS")
                .font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Paper.accent)
            Text(title).font(Typeface.display(22, weight: 430))
            if hasProcedures { procedureList }
            if !data.photos.isEmpty { photoRows }
            Spacer(minLength: 0)
            Text(data.sample ? data.footer : "Logged and photographed by the patient at home. Lighting may vary. Not a medical record.")
                .font(.system(size: 8.5)).foregroundStyle(Paper.ink3)
        }
        .padding(36)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Paper.ink)
    }

    private var title: String {
        if hasProcedures { return data.photos.isEmpty ? "Procedures" : "Procedures and photos" }
        return "Photos, \(data.photos.first?.0.day.short ?? "") – \(data.photos.last?.0.day.short ?? "")"
    }

    private var procedureList: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PROCEDURES").font(.system(size: 8.5, weight: .bold)).tracking(1).foregroundStyle(Paper.ink3)
            ForEach(data.procedures, id: \.id) { p in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(p.day.short).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Paper.ink3).frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(p.title).font(.system(size: 10.5, weight: .semibold))
                            if p.day > data.today {
                                Text("booked").font(.system(size: 9)).foregroundStyle(Paper.accent)
                            }
                        }
                        let info = [p.place == .body ? (data.bodyName ?? "Body") : nil, p.spot, p.clinic, breakText(p)].compactMap { $0 }
                        if !info.isEmpty {
                            Text(info.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(Paper.ink2).lineLimit(1)
                        }
                        if let n = p.note {
                            Text("Aftercare: \(n)").font(.system(size: 9)).foregroundStyle(Paper.ink2).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func breakText(_ p: Procedure) -> String? {
        guard let w = p.breakDays else { return nil }
        return w.from == w.to ? "actives off \(w.from.short)" : "actives off \(w.from.short)–\(w.to.short)"
    }

    private var photoRows: some View {
        // Plain rows: lazy grids don't render inside ImageRenderer.
        let rows = stride(from: 0, to: data.photos.count, by: 3).map { Array(data.photos[$0..<min($0 + 3, data.photos.count)]) }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        let item = rows[r][c]
                        VStack(alignment: .leading, spacing: 2) {
                            Image(uiImage: item.1).resizable().scaledToFill()
                                .frame(width: photoSize.width, height: photoSize.height).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(item.0.place == .body ? "\(data.bodyName ?? "Body") · \(item.0.day.long)" : item.0.day.long)
                                .font(.system(size: 9)).foregroundStyle(Paper.ink3).lineLimit(1)
                            if let c = data.photoContext[item.0.id] {
                                Text(c).font(.system(size: 9, weight: .semibold)).foregroundStyle(Paper.ink2).lineLimit(1)
                            }
                        }
                        .frame(width: photoSize.width, alignment: .leading)
                    }
                }
            }
        }
        .padding(.top, hasProcedures ? 4 : 0)
    }
}
