import AppIntents
import BarrierCore
import SwiftUI
import WidgetKit

struct TonightEntry: TimelineEntry {
    var date: Date
    var configured: Bool
    var slot: Slot = .pm
    var day: Day = Day.routineDay()
    var label: String = "Retinoid night"
    var hue: Hue = .clay
    var steps: [String] = ["Gentle cleanser", "Tretinoin", "Moisturizer"]
    var done = false
    var time = ClockTime(21, 30)
    var pos = 1
    var cycleLen = 3
    var nextLabel: String?

    static let placeholder = TonightEntry(date: Date(), configured: true)
}

struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        var dates = [now]
        // Re-evaluate when the lead routine switches (2 p.m.) and when the day rolls over (4 a.m.).
        for hour in [14, dayRolloverHour] {
            if let d = cal.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime) {
                dates.append(d)
            }
        }
        let entries = dates.sorted().map { entry(at: $0) }
        let refresh = now.addingTimeInterval(3 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    func entry(at date: Date) -> TonightEntry {
        let today = Day.routineDay(date)
        guard let state = SharedStore.currentState(today: today), state.onboarded else {
            return TonightEntry(date: date, configured: false)
        }
        let hour = Calendar.current.component(.hour, from: date)
        let amOn = state.plan.am.enabled && !state.plan.am.steps.isEmpty
        let pmOn = state.plan.pm.enabled && !state.plan.pm.steps.isEmpty
        var slot: Slot = (hour >= 14 || hour < dayRolloverHour) ? .pm : .am
        if slot == .am, amOn, Engine.instance(state, slot: .am, on: today, today: today).isResolved, pmOn { slot = .pm }
        if slot == .am && !amOn { slot = .pm }
        if slot == .pm && !pmOn { slot = .am }
        let inst = Engine.instance(state, slot: slot, on: today, today: today)
        let next = Engine.instance(state, slot: slot, on: today.adding(1), today: today)
        return TonightEntry(
            date: date, configured: true, slot: slot, day: today, label: inst.label, hue: inst.hue,
            steps: inst.steps.map(\.product.name), done: inst.isDone, time: state.plan[slot].time,
            pos: inst.pos, cycleLen: inst.cycleLen, nextLabel: next.steps.isEmpty ? nil : next.label
        )
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BarrierTonight", provider: TonightProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("What to put on your skin tonight, with a Done button.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TonightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TonightEntry

    private var isNight: Bool { entry.slot == .pm }
    private var bg: Color { isNight ? Palette.stage : Color(hex: 0xF4EEE8) }
    private var fg: Color { isNight ? Palette.stageInk : Color(hex: 0x2A231C) }
    private var fg2: Color { isNight ? Palette.stageInk2 : Color(hex: 0x6E6257) }
    private var link: URL? { URL(string: "barrier://ritual/\(entry.slot.rawValue)/\(entry.day.iso)") }

    var body: some View {
        Group {
            if !entry.configured {
                setup
            } else {
                switch family {
                case .accessoryRectangular: rectangular
                case .accessoryCircular: circular
                case .accessoryInline: inline
                case .systemMedium: medium
                default: small
                }
            }
        }
        .widgetURL(link)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "moon.stars").font(.title3)
            Text("Open Barrier to set up your routine.").font(.footnote.weight(.medium))
        }
        .foregroundStyle(Palette.stageInk)
        .containerBackground(Palette.stage, for: .widget)
    }

    private var kicker: String {
        entry.done ? (isNight ? "Tonight · done" : "Morning · done") : (isNight ? "Tonight · \(entry.time.short)" : "Morning · \(entry.time.short)")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(entry.hue.color).frame(width: 12, height: 12)
                Spacer()
                if entry.cycleLen > 1 && !entry.done {
                    Text("\(entry.pos + 1)/\(entry.cycleLen)").font(.caption2.weight(.semibold)).foregroundStyle(fg2)
                }
            }
            Spacer()
            Text(kicker.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(fg2)
            Text(entry.label)
                .font(Typeface.display(20, weight: 450))
                .foregroundStyle(fg)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
            Text(entry.done ? (entry.nextLabel.map { "Next: \($0.lowercased())" } ?? "Nice work.") : "\(entry.steps.count) step\(entry.steps.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(fg2)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .containerBackground(bg, for: .widget)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Circle().fill(entry.hue.color).frame(width: 12, height: 12)
                Spacer()
                Text(kicker.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(fg2)
                Text(entry.label)
                    .font(Typeface.display(21, weight: 450))
                    .foregroundStyle(fg)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(entry.steps.prefix(4).enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 6) {
                        Text("\(i + 1)").font(.caption2.monospacedDigit()).foregroundStyle(fg2)
                        Text(s).font(.caption.weight(.medium)).foregroundStyle(fg).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if entry.done {
                    Label("Done", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(entry.hue.color)
                } else {
                    Button(intent: MarkRoutineDoneIntent(routine: isNight ? .evening : .morning)) {
                        Label("Done", systemImage: "checkmark").font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isNight ? Palette.stage : .white)
                    .background(isNight ? entry.hue.color : Color(hex: 0xA6512E), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(bg, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(isNight ? "TONIGHT" : "THIS MORNING").font(.system(size: 11, weight: .semibold))
            Text(entry.label).font(.headline).lineLimit(1)
            Text(entry.done ? "Done ✓" : "\(entry.steps.count) steps · \(entry.time.short)").font(.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.done {
                Image(systemName: "checkmark").font(.title3.weight(.bold))
            } else if entry.cycleLen > 1 {
                VStack(spacing: 0) {
                    Image(systemName: isNight ? "moon.fill" : "sun.max.fill").font(.caption)
                    Text("\(entry.pos + 1)/\(entry.cycleLen)").font(.caption2.weight(.semibold))
                }
            } else {
                Image(systemName: isNight ? "moon.fill" : "sun.max.fill").font(.title3)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        Text(entry.done ? "\(isNight ? "Tonight" : "Morning") done ✓" : "\(entry.label) · \(entry.time.short)")
            .containerBackground(.clear, for: .widget)
    }
}

extension ClockTime {
    /// "9:30 PM" in the widget (no access to the app's helpers).
    var short: String {
        let d = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}

