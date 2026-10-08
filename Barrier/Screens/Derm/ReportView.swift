import BarrierCore
import SwiftUI

/// A one- or two-page report for the dermatologist: plan, adherence, skin log,
/// questions and photos. Rendered as A4 PDF pages, previewed as images.
struct ReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [UIImage] = []
    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if pages.isEmpty {
                        ProgressView().padding(.top, 80)
                    }
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    }
                    Text("Logged by you in Barrier. Not a medical record.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .task { render() }
        }
    }

    @MainActor
    private func render() {
        let data = ReportData(state: model.state, today: model.today, photos: model.photos)
        var views: [AnyView] = [AnyView(ReportPageOne(data: data))]
        if !data.photos.isEmpty { views.append(AnyView(ReportPhotosPage(data: data))) }
        let size = CGSize(width: 595, height: 842)
        pages = views.compactMap { v in
            let r = ImageRenderer(content: v.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
            r.scale = 2
            return r.uiImage
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Barrier report \(model.today.iso).pdf")
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
        pdfURL = url
    }
}

/// Everything the report shows, computed once.
struct ReportData {
    struct StepLine: Hashable { var name: String; var detail: String }

    var today: Day
    var from: Day
    var followUp: FollowUp?
    var pmSteps: [StepLine]
    var amSteps: [StepLine]
    var rotation: String?
    var easing: String?
    var products: [Product]
    var nightsDone: Int
    var nightsDue: Int
    var last28: (done: Int, due: Int)
    var morningsDone: Int
    var byLabel: [(String, Int)]
    var skipped: Int
    var recovery: Int
    var pauses: [Pause]
    var checkins: [CheckIn]
    var questions: [Question]
    var notes: String?
    var ifIrritated: String?
    var photos: [(PhotoMeta, UIImage)]

    @MainActor
    init(state s: AppState, today: Day, photos store: PhotoStore) {
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
        rotation = s.plan.pm.length > 1 ? "Evening repeats every \(s.plan.pm.length) nights." : nil
        if let e = s.plan.pm.easeIn {
            let end = e.start.adding(e.totalDays)
            easing = end > today ? "Easing in since \(e.start.short), full routine from \(end.short)." : "Eased in from \(e.start.short) to \(end.short)."
        }
        let used = Set((s.plan.am.steps + s.plan.pm.steps).map(\.productId))
        self.products = s.products.filter { used.contains($0.id) && ($0.kind.isActive || $0.kind == .oral || $0.note != nil) }
        let st = Engine.stats(s, today: today)
        nightsDone = st.nightsDone
        morningsDone = st.morningsDone
        last28 = (st.last28Done, st.last28Due)
        let tl = s.plan.pm.enabled && s.plan.createdAt <= today ? Engine.timeline(s, slot: .pm, from: s.plan.createdAt, to: today, today: today) : []
        nightsDue = tl.filter { $0.status != .off && $0.status != .pending }.count
        byLabel = st.byLabel.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        skipped = st.skipped
        recovery = st.recoveryNights
        pauses = s.pauses.filter { $0.from <= today }
        checkins = Array(s.checkins.sorted { $0.day > $1.day }.prefix(12))
        questions = s.questions.sorted { !$0.answered && $1.answered }
        notes = s.plan.dermNotes
        ifIrritated = s.plan.ifIrritated
        // First, a middle one, and the latest few.
        let sorted = s.photos.sorted { $0.at < $1.at }
        var pick: [PhotoMeta] = []
        if let f = sorted.first { pick.append(f) }
        if sorted.count > 2 { pick.append(sorted[sorted.count / 2]) }
        for p in sorted.suffix(4) where !pick.contains(p) { pick.append(p) }
        photos = Array(pick.suffix(6)).compactMap { m in store.image(m.id).map { (m, $0) } }
    }
}

private enum Paper {
    static let ink = Color(hex: 0x1B2A26)
    static let ink2 = Color(hex: 0x485853)
    static let ink3 = Color(hex: 0x6B7772)
    static let line = Color(hex: 0x1B2A26, alpha: 0.14)
    static let accent = Color(hex: 0xA6512E)
}

struct ReportPageOne: View {
    var data: ReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    block("Evening routine") {
                        if let r = data.rotation { small(r) }
                        if let e = data.easing { small(e) }
                        steps(data.pmSteps)
                    }
                    if !data.amSteps.isEmpty {
                        block("Morning routine") { steps(data.amSteps) }
                    }
                    if !data.products.isEmpty {
                        block("Treatments") {
                            ForEach(data.products, id: \.id) { p in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.system(size: 10, weight: .semibold))
                                    small([p.from.map { "since \($0.short)" }, p.until.map { "until \($0.short)" }, p.note].compactMap { $0 }.joined(separator: " · "))
                                }
                            }
                        }
                    }
                }
                .frame(width: 250, alignment: .leading)
                VStack(alignment: .leading, spacing: 14) {
                    block("How it went") {
                        stat("\(data.nightsDone) of \(data.nightsDue)", "evenings done since \(data.from.short)")
                        if data.last28.due >= 5 { stat("\(data.last28.done) of \(data.last28.due)", "evenings, last 4 weeks") }
                        if data.morningsDone > 0 { stat("\(data.morningsDone)", "mornings logged") }
                        if data.recovery > 0 { stat("\(data.recovery)", "recovery nights for irritation") }
                        if !data.byLabel.isEmpty {
                            small(data.byLabel.map { "\($0.0): \($0.1)" }.joined(separator: " · "))
                        }
                        ForEach(data.pauses, id: \.id) { p in small("Paused \(p.from.short)–\(p.to.short): \(p.reason.label.lowercased())") }
                    }
                    block("Skin log") {
                        if data.checkins.isEmpty { small("No check-ins yet.") }
                        ForEach(data.checkins, id: \.day) { c in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(c.day.short).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Paper.ink3).frame(width: 40, alignment: .leading)
                                Text(([c.feel.map(\.label).joined(separator: ", ")] + [c.note].compactMap { $0 }).joined(separator: ": "))
                                    .font(.system(size: 9.5, weight: c.feel.contains(where: \.isIrritation) ? .semibold : .regular))
                                    .foregroundStyle(c.feel.contains(where: \.isIrritation) ? Color(hex: 0xA4402F) : Paper.ink)
                            }
                        }
                    }
                }
            }
            if !data.questions.isEmpty {
                block("Questions") {
                    ForEach(data.questions.prefix(8), id: \.id) { q in
                        HStack(alignment: .top, spacing: 6) {
                            Text(q.answered ? "✓" : "•").font(.system(size: 10, weight: .bold)).foregroundStyle(Paper.accent)
                            Text(q.text).font(.system(size: 10.5)).foregroundStyle(q.answered ? Paper.ink3 : Paper.ink)
                        }
                    }
                }
            }
            if data.notes != nil || data.ifIrritated != nil {
                block("Instructions noted") {
                    if let a = data.notes { small(a) }
                    if let b = data.ifIrritated { small("If irritated: \(b)") }
                }
            }
            Spacer(minLength: 0)
            Text("Logged by the patient in Barrier on \(data.today.long). Not a medical record.")
                .font(.system(size: 8.5)).foregroundStyle(Paper.ink3)
        }
        .padding(36)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Paper.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BARRIER · SKIN ROUTINE REPORT").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Paper.accent)
            Text("\(data.from.short) – \(data.today.short)").font(Typeface.display(26, weight: 430))
            if let fu = data.followUp {
                Text("For the visit on \(fu.day.long)\(fu.with.map { " with \($0)" } ?? "")").font(.system(size: 11)).foregroundStyle(Paper.ink2)
            }
            Rectangle().fill(Paper.line).frame(height: 1).padding(.top, 6)
        }
    }

    private func block<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 8.5, weight: .bold)).tracking(1).foregroundStyle(Paper.ink3)
            content()
        }
    }

    private func steps(_ lines: [ReportData.StepLine]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(i + 1)").font(.system(size: 9).monospacedDigit()).foregroundStyle(Paper.ink3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.name).font(.system(size: 10.5, weight: .semibold))
                        Text(l.detail).font(.system(size: 9)).foregroundStyle(Paper.ink2)
                    }
                }
            }
        }
    }

    private func stat(_ big: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(big).font(.system(size: 13, weight: .semibold).monospacedDigit())
            Text(label).font(.system(size: 9.5)).foregroundStyle(Paper.ink2)
        }
    }

    private func small(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5)).foregroundStyle(Paper.ink2).fixedSize(horizontal: false, vertical: true)
    }
}

struct ReportPhotosPage: View {
    var data: ReportData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BARRIER · PROGRESS PHOTOS").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Paper.accent)
            Text("Photos, \(data.photos.first?.0.day.short ?? "") – \(data.photos.last?.0.day.short ?? "")").font(Typeface.display(22, weight: 430))
            let cols = Array(repeating: GridItem(.fixed(166), spacing: 12), count: 3)
            LazyVGrid(columns: cols, alignment: .leading, spacing: 14) {
                ForEach(Array(data.photos.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Image(uiImage: item.1).resizable().scaledToFill().frame(width: 166, height: 221).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(item.0.day.long).font(.system(size: 9)).foregroundStyle(Paper.ink3)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Taken by the patient at home. Lighting may vary.").font(.system(size: 8.5)).foregroundStyle(Paper.ink3)
        }
        .padding(36)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Paper.ink)
    }
}
