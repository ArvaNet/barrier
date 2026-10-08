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

    var body: some View {
        let today = model.today
        let stats = Engine.stats(model.state, today: today)
        NavigationStack {
            Page(spacing: 18) {
                Text("Progress").font(.barrierTitle).foregroundStyle(Palette.ink).padding(.top, 6)
                summary(stats)
                ringsCard
                calendarCard(today)
                photosCard
                skinLog(today)
                if !stats.byLabel.isEmpty { byNight(stats) }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $detailDay) { d in
            DayDetailSheet(day: d).barrier(model).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showCamera) { CameraScreen().barrier(model) }
        .sheet(item: $compare) { pair in CompareView(pair: pair).barrier(model) }
        .sheet(item: $viewing) { photo in PhotoDetail(photo: photo).barrier(model) }
        .onChange(of: pickerItem) { _, item in importPhoto(item) }
    }

    // MARK: Summary

    private func summary(_ stats: Engine.Stats) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(stats.nightsDone)")
                    .font(Typeface.display(64, weight: 380))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Palette.ink)
                Text(stats.nightsDone == 1 ? "night done" : "nights done").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if stats.last28Due >= 5 {
                    Text("\(stats.last28Done) of \(stats.last28Due)").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
                    Text("nights, last 4 weeks").font(.footnote).foregroundStyle(Palette.ink3)
                } else if let first = stats.firstDay {
                    Text("since \(first.short)").font(.subheadline).foregroundStyle(Palette.ink3)
                }
                if stats.morningsDone > 0 {
                    Text("\(stats.morningsDone) mornings").font(.footnote).foregroundStyle(Palette.ink3)
                }
            }
        }
        .card()
    }

    private var ringsCard: some View {
        let rings = Engine.rings(model.state, today: model.today)
        let byCycle = model.state.plan.pm.length >= 3
        return VStack(alignment: .leading, spacing: 12) {
            Kicker("Your rings")
            if rings.isEmpty {
                Text("Your first ring starts tonight.").font(.subheadline).foregroundStyle(Palette.ink2)
            } else {
                RingsView(rings: rings, size: 240).frame(maxWidth: .infinity)
                Text(byCycle ? "One ring per cycle, from the center out. Filled nights are done." : "One ring per week, from the center out. Filled nights are done.")
                    .font(.footnote).foregroundStyle(Palette.ink3)
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
        let pmBy = Dictionary(pm.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let amBy = Dictionary(am.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let cells: [Day?] = Array(repeating: nil, count: lead) + (0..<count).map { first.adding($0) }
        let rows: [[Day?]] = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(first.date().formatted(.dateTime.month(.wide).year())).font(.barrierH3).foregroundStyle(Palette.ink)
                Spacer()
                Button { month = month.addingMonths(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 36) }
                    .accessibilityLabel("Previous month")
                Button { month = month.addingMonths(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 36) }
                    .accessibilityLabel("Next month")
            }
            .foregroundStyle(Palette.ink2)
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
                                calendarCell(d, today: today, pm: pmBy[d], am: amBy[d])
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
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(Palette.ink3)
        }
        .card()
    }

    private func calendarCell(_ d: Day, today: Day, pm: Instance?, am: Instance?) -> some View {
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
                }
                .frame(height: 9)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.long)\(pm?.isDone == true ? ", evening done" : "")\(am?.isDone == true ? ", morning done" : "")")
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
        let photos = model.state.photos.sorted { $0.at > $1.at }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Kicker("Photos")
                Spacer()
                if photos.count >= 2 {
                    Button(selecting ? "Cancel" : "Compare") {
                        selecting.toggle()
                        selected = []
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                }
            }
            if selecting {
                Text(selected.isEmpty ? "Pick two photos." : "Pick one more.").font(.footnote).foregroundStyle(Palette.ink3)
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
                Text("Your first photo is your “before”. Same spot, window light, no makeup.")
                    .font(.footnote).foregroundStyle(Palette.ink3)
            } else {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(photos) { ph in
                        PhotoThumb(photo: ph, selected: selected.contains(ph.id))
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
                let meta = PhotoMeta(day: model.today)
                do {
                    try model.photos.save(img, id: meta.id)
                    model.update { $0.photos.append(meta) }
                    model.show("Photo added.")
                } catch {
                    model.show("Couldn’t save that photo.")
                }
            }
            pickerItem = nil
        }
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
                ForEach(recent.prefix(8), id: \.day) { c in
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.day.short).font(.subheadline.monospacedDigit()).foregroundStyle(Palette.ink3).frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.feel.map(\.label).joined(separator: ", "))
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

    private func byNight(_ stats: Engine.Stats) -> some View {
        let rows = stats.byLabel.sorted { $0.value > $1.value }
        let top = rows.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Kicker("By night")
            ForEach(rows, id: \.key) { row in
                let label = row.key
                let n = row.value
                HStack(spacing: 10) {
                    Text(label).font(.subheadline).foregroundStyle(Palette.ink).frame(width: 150, alignment: .leading).lineLimit(1)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hue(for: label).color)
                        .frame(width: max(6, 120 * CGFloat(n) / CGFloat(max(1, top))), height: 10)
                    Spacer(minLength: 0)
                    Text("\(n)").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.ink2).frame(width: 30, alignment: .trailing)
                }
            }
        }
        .card()
    }

    private func hue(for label: String) -> Hue {
        model.state.log.last { $0.label == label }?.hue ?? .sage
    }
}

struct ComparePair: Identifiable {
    var before: PhotoMeta
    var after: PhotoMeta
    var id: String { before.id + after.id }
}

struct PhotoThumb: View {
    @Environment(AppModel.self) private var model
    var photo: PhotoMeta
    var selected = false
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Palette.surface2)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
            Text(photo.day.short)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .padding(6)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Palette.accent : .clear, lineWidth: 3))
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        photo(pair.after)
                        photo(pair.before)
                            .mask(alignment: .leading) { Rectangle().frame(width: g.size.width * split) }
                        Rectangle().fill(.white).frame(width: 2).offset(x: g.size.width * split - 1)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                        Circle().fill(.white).frame(width: 36, height: 36)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(.black))
                            .shadow(color: .black.opacity(0.3), radius: 6)
                            .offset(x: g.size.width * split - 18, y: g.size.height / 2 - 18)
                        label(pair.before.day.short).padding(10)
                        label(pair.after.day.short).padding(10).frame(maxWidth: .infinity, alignment: .trailing)
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
                Text("\(pair.before.day.days(to: pair.after.day)) days apart. Drag to compare.")
                    .font(.subheadline).foregroundStyle(Palette.ink3)
                Spacer()
            }
            .padding()
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Before and after")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func photo(_ p: PhotoMeta) -> some View {
        GeometryReader { g in
            if let img = model.photos.image(p.id) {
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
