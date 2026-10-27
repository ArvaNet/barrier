import BarrierCore
import PhotosUI
import SwiftUI

struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @State private var month: Day = Day.routineDay().firstOfMonth
    @State private var detailDay: Day?
    @State private var showCamera = false
    @State private var selecting = false
    @State private var selected: [String] = []
    @State private var compare: ComparePair?
    @State private var viewing: PhotoMeta?
    @State private var pickerItem: PhotosPickerItem?
    /// Photo filter; nil = all areas.
    @State private var photoArea: Area?
    /// An imported photo waiting for "Which area?".
    @State private var pendingImport: PendingImport?
    @State private var showLegend = false
    @State private var showFillIn = false

    var body: some View {
        let today = model.today
        let stats = Engine.stats(model.state, today: today)
        NavigationStack {
            Page(spacing: 16) {
                // The rings first (the signature), then photos (the reason it's worth it),
                // then the timeline and calendar for detail.
                ringsHero(stats)
                photosCard
                timelineCard
                calendarCard(today)
                skinLog(today)
            }
            .navigationTitle("Progress")
        }
        .sheet(item: $detailDay) { d in
            DayDetailSheet(day: d).barrier(model).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCamera) { CameraScreen(initialArea: effectiveArea ?? .face).barrier(model) }
        .confirmationDialog("Which area is this photo?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("Face") {
                if let p = pendingImport { saveImport(p, area: .face) }
                pendingImport = nil
            }
            Button(model.bodyAreaName) {
                if let p = pendingImport { saveImport(p, area: .body) }
                pendingImport = nil
            }
        }
        .sheet(item: $compare) { pair in CompareView(pair: pair).barrier(model) }
        .sheet(item: $viewing) { photo in PhotoDetail(photo: photo).barrier(model) }
        .onChange(of: pickerItem) { _, item in importPhoto(item) }
        .sheet(isPresented: $showFillIn) {
            FillInSheet(start: FillInSheet.suggestedStart(model.state, today: model.today)).barrier(model)
        }
        .onAppear {
            // Screenshot hook: `-screen fill-in`.
            if model.launch.screen == "fill-in", FillInSheet.available(model.state, today: model.today) { showFillIn = true }
        }
    }

    // MARK: Summary

    /// The growth rings with the night count inside, and three numbers under them.
    private func ringsHero(_ stats: Engine.Stats) -> some View {
        let rings = Engine.rings(model.state, today: model.today)
        let byCycle = model.state.plan.pm.length >= 3
        var cells: [(String, String)] = []
        if stats.last28Due >= 5 {
            cells.append(("\(stats.last28Done) of \(stats.last28Due)", "last 4 weeks"))
        } else if let first = stats.firstDay {
            cells.append((first.short, "first night"))
        }
        if stats.morningsDone > 0 { cells.append(("\(stats.morningsDone)", "mornings")) }
        if stats.bodyDone > 0 { cells.append(("\(stats.bodyDone)", "\(model.bodyAreaName.lowercased()) routines")) }
        // Day one (nothing done yet): the first ring, waiting, not a stray arc.
        let waiting = rings.isEmpty || stats.nightsDone == 0
        return VStack(spacing: 16) {
            ZStack {
                if waiting {
                    Circle()
                        .strokeBorder(Palette.line2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                        .frame(width: 200, height: 200)
                } else {
                    AnimatedRings(rings: rings, size: 240)
                }
                VStack(spacing: 0) {
                    Text("\(stats.nightsDone)")
                        .font(.barrierNumeral).tracking(-1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Palette.ink)
                    Text(waiting ? "Your first ring\nstarts tonight" : (stats.nightsDone == 1 ? "night" : "nights"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink3)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            if !cells.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Rectangle().fill(Palette.line).frame(width: 1, height: 32) }
                        VStack(spacing: 2) {
                            Text(c.0).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
                            Text(c.1).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1).minimumScaleFactor(0.85)
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if !waiting {
                Text(byCycle ? "One ring per cycle, from the center out. Filled nights are done." : "One ring per week, from the center out. Filled nights are done.")
                    .font(.footnote).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // New to Barrier but not to the routine: the weeks before can count too.
            if offerFillIn {
                Button {
                    showFillIn = true
                } label: {
                    Label("Followed it before? Fill in those weeks", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(TertiaryButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, -4)
            }
        }
        .card()
    }

    /// The first four weeks, until something's been filled in.
    private var offerFillIn: Bool {
        let s = model.state
        return FillInSheet.available(s, today: model.today) && s.filledInSpan == nil
            && s.plan.createdAt.days(to: model.today) < 28
    }

    // MARK: Timeline

    /// The last eight weeks at a glance: the same picture the report opens with.
    private var timelineCard: some View {
        let data = TreatmentTimeline.build(model.state, today: model.today, maxDays: 56)
        let height = TimelineStrip(data: data, width: 0).height
        let recent = Array(data.changes.suffix(3))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Kicker(data.days >= 56 ? "Timeline · last 8 weeks" : "Timeline · since \(data.from.short)")
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showLegend.toggle() }
                } label: {
                    Label(showLegend ? "Hide key" : "How to read", systemImage: "info.circle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.ink2)
                        .frame(minHeight: 44)
                }
                .padding(.vertical, -12)
            }
            GeometryReader { g in
                TimelineStrip(data: data, width: g.size.width)
            }
            .frame(height: height)
            if showLegend {
                TimelineLegend().transition(.opacity)
            }
            if !data.earlier.isEmpty {
                Text("Earlier: " + data.earlier.map { "\($0.name), \($0.day.short)" }.joined(separator: "; "))
                    .font(.footnote).foregroundStyle(Palette.ink3)
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recent, id: \.number) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            ZStack {
                                Circle().fill(Palette.ink)
                                Text("\(c.number)").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.surface)
                            }
                            .frame(width: 16, height: 16)
                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 4 }
                            Text("\(c.change.day.short) · \(c.change.lines.joined(separator: "; "))")
                                .font(.footnote).foregroundStyle(Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .card()
    }

    // MARK: Calendar

    private func calendarCard(_ today: Day) -> some View {
        let first = month
        let lead = (first.weekday + 6) % 7 // Monday-first
        let count = first.daysInMonth
        let end = first.adding(count - 1)
        let from = max(first, model.state.plan.createdAt)
        let pm = from <= min(end, today.adding(30)) ? Engine.timeline(model.state, slot: .pm, from: from, to: min(end, today.adding(30)), today: today) : []
        let am = from <= min(end, today.adding(30)) ? Engine.timeline(model.state, slot: .am, from: from, to: min(end, today.adding(30)), today: today) : []
        let body = model.hasBodyRoutine && from <= min(end, today.adding(30))
            ? model.state.plan.bodySlots.flatMap { Engine.timeline(model.state, slot: $0, from: from, to: min(end, today.adding(30)), today: today) }.filter { !$0.steps.isEmpty || $0.entry != nil }
            : []
        let pmBy = Dictionary(pm.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let amBy = Dictionary(am.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        // Two body routines share one dot: it fills once both are done.
        let bodyBy = Dictionary(body.map { ($0.day, $0) }, uniquingKeysWith: { a, b in a.isDone ? b : a })
        let procBy = Dictionary(model.state.procedures.filter { $0.day >= first && $0.day <= end }.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let cells: [Day?] = Array(repeating: nil, count: lead) + (0..<count).map { first.adding($0) }
        let rows: [[Day?]] = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(first.date().formatted(.dateTime.month(.wide).year())).font(.barrierH3).foregroundStyle(Palette.ink)
                Spacer()
                Button { month = month.addingMonths(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Button { month = month.addingMonths(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
            }
            .foregroundStyle(Palette.ink2)
            .padding(.vertical, -8)
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(letters[i]).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<rows.count, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { c in
                            if c < rows[r].count, let d = rows[r][c] {
                                calendarCell(d, today: today, pm: pmBy[d], am: amBy[d], body: bodyBy[d], procedure: procBy[d])
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legend(filled: true, "Done")
                legend(filled: false, "Planned")
                if model.hasBodyRoutine {
                    HStack(spacing: 5) {
                        Circle().fill(Hue.lilac.color).frame(width: 5, height: 5)
                        Text(model.bodyAreaName)
                    }
                }
                if !procBy.isEmpty {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Palette.accent, lineWidth: 1.4).frame(width: 10, height: 10)
                        Text("Procedure")
                    }
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(Palette.ink3)
        }
        .card()
    }

    private func calendarCell(_ d: Day, today: Day, pm: Instance?, am: Instance?, body: Instance?, procedure: Procedure?) -> some View {
        let isToday = d == today
        return Button {
            detailDay = d
        } label: {
            VStack(spacing: 4) {
                Text("\(d.day)")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Palette.ink : (d > today ? Palette.ink3 : Palette.ink2))
                HStack(spacing: 3) {
                    dot(am, small: true)
                    dot(pm, small: false)
                    if model.hasBodyRoutine { dot(body, small: true) }
                }
                .frame(height: 9)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface2)
                }
            }
            .overlay {
                if procedure != nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.accent, lineWidth: 1.4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.long)\(procedure.map { ", \($0.name)" } ?? "")\(pm?.isDone == true ? ", evening done" : "")\(am?.isDone == true ? ", morning done" : "")\(body?.isDone == true ? ", \(model.bodyAreaName.lowercased()) done" : "")")
    }

    @ViewBuilder
    private func dot(_ inst: Instance?, small: Bool) -> some View {
        let s: CGFloat = small ? 5 : 8
        if let inst, inst.status != .off, !inst.steps.isEmpty || inst.isDone {
            if inst.isDone {
                Circle().fill(inst.hue.color).frame(width: s, height: s)
            } else if inst.status == .future || inst.status == .pending {
                Circle().strokeBorder(inst.hue.color.opacity(0.7), lineWidth: 1.2).frame(width: s, height: s)
            } else {
                Circle().strokeBorder(Palette.line2, lineWidth: 1).frame(width: s, height: s)
            }
        } else {
            Color.clear.frame(width: s, height: s)
        }
    }

    private func legend(filled: Bool, _ text: String) -> some View {
        HStack(spacing: 5) {
            if filled { Circle().fill(Hue.clay.color).frame(width: 8, height: 8) } else { Circle().strokeBorder(Hue.clay.color, lineWidth: 1.2).frame(width: 8, height: 8) }
            Text(text)
        }
    }

    // MARK: Photos

    private var photosCard: some View {
        let showAreas = showsAreas
        let filter = effectiveArea
        let photos = model.state.photos.filter { filter == nil || $0.place == filter }.sorted { $0.at > $1.at }
        let canCompare = photos.contains { p in photos.filter { $0.matches(p) }.count >= 2 }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Kicker("Photos")
                Spacer()
                if canCompare {
                    Button(selecting ? "Cancel" : "Compare") {
                        selecting.toggle()
                        selected = []
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                }
            }
            if showAreas {
                Picker("Area", selection: $photoArea) {
                    Text("All").tag(Area?.none)
                    Text("Face").tag(Area?.some(.face))
                    Text(model.bodyAreaName).tag(Area?.some(.body))
                }
                .pickerStyle(.segmented)
                .onChange(of: photoArea) { _, _ in
                    selecting = false
                    selected = []
                }
            }
            if selecting {
                Text(selected.isEmpty ? "Pick two photos of the same view (front, left or right)." : "Pick one more of the same view.").font(.footnote).foregroundStyle(Palette.ink3)
            }
            HStack(spacing: 10) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Import", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            if photos.isEmpty {
                // Day one: a tile waiting for the "before", not an empty card.
                Button {
                    showCamera = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                                .strokeBorder(Palette.line2, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            Image(systemName: "camera").font(.title3).foregroundStyle(Palette.ink2)
                        }
                        .frame(width: 72, height: 96)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your before").font(.barrierH3).foregroundStyle(Palette.ink)
                            Text("Same spot, window light, no makeup. In a few weeks you’ll be glad it exists.")
                                .font(.footnote).foregroundStyle(Palette.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(photos) { ph in
                        PhotoThumb(photo: ph, selected: selected.contains(ph.id), areaName: showAreas && photoArea == nil ? areaName(ph.place) : nil)
                            .onTapGesture { tapPhoto(ph) }
                    }
                }
            }
        }
        .card()
    }

    private func tapPhoto(_ ph: PhotoMeta) {
        guard selecting else {
            viewing = ph
            return
        }
        if let i = selected.firstIndex(of: ph.id) {
            selected.remove(at: i)
            return
        }
        // A face next to a back, or a side next to the front, isn't a comparison.
        if let first = selected.first, let other = model.state.photos.first(where: { $0.id == first }), !other.matches(ph) {
            let view = other.place == .face && other.angle != .front ? "\(other.angle.label.lowercased()) side" : areaName(other.place).lowercased()
            model.show("Pick two \(view) photos.")
            return
        }
        selected.append(ph.id)
        if selected.count == 2 {
            let pair = model.state.photos.filter { selected.contains($0.id) }.sorted { $0.at < $1.at }
            if pair.count == 2 { compare = ComparePair(before: pair[0], after: pair[1]) }
            selecting = false
            selected = []
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                let pending = PendingImport(image: img, taken: PhotoDate.taken(data))
                if showsAreas && effectiveArea == nil {
                    // Under "All", ask which area it is: it can't be changed later.
                    pendingImport = pending
                } else {
                    saveImport(pending, area: effectiveArea ?? .face)
                }
            }
            pickerItem = nil
        }
    }

    /// Dated when it was taken, so a before photo imported later still pairs as the before.
    private func saveImport(_ p: PendingImport, area: Area) {
        let day = p.taken.map { Day.routineDay($0) } ?? model.today
        let meta = PhotoMeta(day: day, at: p.taken ?? Date(), area: area)
        do {
            try model.photos.save(p.image, id: meta.id)
            model.update { $0.photos.append(meta) }
            model.show(day == model.today ? "Photo added." : "Photo added, dated \(day.short).")
        } catch {
            model.show("Couldn’t save that photo.")
        }
    }

    /// Face/body choice shows when there's a body routine or body photos.
    private var showsAreas: Bool {
        model.hasBodyRoutine || model.state.photos.contains { $0.place == .body }
    }

    /// The filter, ignored when area choice isn't shown.
    private var effectiveArea: Area? { showsAreas ? photoArea : nil }

    private func areaName(_ a: Area) -> String {
        a == .face ? "Face" : model.bodyAreaName
    }

    // MARK: Skin log

    private func skinLog(_ today: Day) -> some View {
        let recent = model.state.checkins.filter { $0.day >= today.adding(-41) }.sorted { $0.day > $1.day }
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("Skin log")
            if recent.isEmpty {
                Text("Check in from Today. A tap a day builds a record your dermatologist can actually use.")
                    .font(.footnote).foregroundStyle(Palette.ink3)
            } else {
                ForEach(recent.prefix(10), id: \.self) { c in
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.day.short).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.ink3).frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((c.place == .body ? "\(areaName(.body)): " : "") + c.feel.map(\.label).joined(separator: ", "))
                                .font(.subheadline.weight(c.feel.contains(where: \.isIrritation) ? .semibold : .regular))
                                .foregroundStyle(c.feel.contains(where: \.isIrritation) ? Palette.danger : Palette.ink)
                            if let n = c.note { Text(n).font(.footnote).foregroundStyle(Palette.ink3) }
                        }
                        Spacer()
                    }
                }
            }
        }
        .card()
    }

}

/// A picked photo and when it was taken (from its metadata, if it has any).
struct PendingImport {
    var image: UIImage
    var taken: Date?
}

struct ComparePair: Identifiable {
    var before: PhotoMeta
    var after: PhotoMeta
    /// For a procedure: its name, and a caption that says how long after.
    var title: String? = nil
    var caption: String? = nil
    var id: String { before.id + after.id }
}

struct PhotoThumb: View {
    @Environment(AppModel.self) private var model
    var photo: PhotoMeta
    var selected = false
    /// Shown when the grid mixes face and body photos.
    var areaName: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Palette.surface2)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
            // A side photo says which side, so a grid of mixed views still reads.
            let view = photo.place == .face && photo.angle != .front ? photo.angle.label : nil
            Text(([areaName, view].compactMap { $0 } + [photo.day.short]).joined(separator: " · "))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .padding(6)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Palette.ink : .clear, lineWidth: 3))
        .contentShape(Rectangle())
        .task(id: photo.id) { image = model.photos.image(photo.id, thumb: true) }
        .accessibilityLabel("Photo from \(photo.day.long)")
        .accessibilityAddTraits(.isButton)
    }
}

struct PhotoDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var photo: PhotoMeta
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack {
                if let img = model.photos.image(photo.id) {
                    Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ContentUnavailableView("Photo missing", systemImage: "photo")
                }
                // "5 weeks after Subcision": where this photo sits among procedures.
                if let context = Procedures.context(photo, in: model.state) {
                    Text(context).font(.subheadline).foregroundStyle(Palette.ink3).padding(.top, 8)
                }
                Spacer()
            }
            .padding()
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(photo.day.long)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let img = model.photos.image(photo.id) {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(photo.day.long, image: Image(uiImage: img)))
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete photo")
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.photos.delete(photo.id)
                    model.update { $0.photos.removeAll { $0.id == photo.id } }
                    dismiss()
                }
            }
        }
    }
}

/// Before and after with a drag handle.
struct CompareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var pair: ComparePair
    @State private var split: CGFloat = 0.5
    @State private var before: UIImage?
    @State private var after: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        photo(after)
                        photo(before)
                            .mask(alignment: .leading) { Rectangle().frame(width: g.size.width * split) }
                        Rectangle().fill(.white).frame(width: 2).offset(x: g.size.width * split - 1)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                        Circle().fill(.white).frame(width: 36, height: 36)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(.black))
                            .shadow(color: .black.opacity(0.3), radius: 6)
                            .offset(x: g.size.width * split - 18, y: g.size.height / 2 - 18)
                        label(pair.title == nil ? pair.before.day.short : "Before · \(pair.before.day.short)").padding(10)
                        label(pair.title == nil ? pair.after.day.short : "After · \(pair.after.day.short)").padding(10).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(width: g.size.width, height: g.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        split = min(1, max(0, v.location.x / g.size.width))
                    })
                    .accessibilityElement()
                    .accessibilityLabel("Before \(pair.before.day.long), after \(pair.after.day.long)")
                    .accessibilityAdjustableAction { dir in
                        split = min(1, max(0, split + (dir == .increment ? 0.1 : -0.1)))
                    }
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                Text(pair.caption ?? "\(pair.before.day.days(to: pair.after.day)) days apart. Drag to compare.")
                    .font(.subheadline).foregroundStyle(Palette.ink3)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .background(Palette.bg.ignoresSafeArea())
            .task {
                before = model.photos.image(pair.before.id)?.resized(maxSide: 1400)
                after = model.photos.image(pair.after.id)?.resized(maxSide: 1400)
            }
            .navigationTitle(pair.title ?? "Before and after")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func photo(_ img: UIImage?) -> some View {
        GeometryReader { g in
            if let img {
                Image(uiImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
            } else {
                Color.black
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
