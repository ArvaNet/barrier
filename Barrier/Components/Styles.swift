import BarrierCore
import SwiftUI

// MARK: - Surfaces

/// Motion (Apple's fluid-interface rules): springs, not fixed curves, so anything can be
/// interrupted mid-flight. Critically damped by default; bounce only after a flick.
enum Motion {
    /// The house default: no overshoot, settles calmly.
    static let ui = Animation.spring(response: 0.35, dampingFraction: 1)
    /// Press feedback: on touch-down, quick.
    static let press = Animation.spring(response: 0.22, dampingFraction: 1)
    /// Only where the gesture carried momentum (the orbit turning after "done").
    static let momentum = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// The default, or nothing under Reduce Motion (callers cross-fade instead).
    static func ui(_ reduce: Bool) -> Animation? { reduce ? .easeInOut(duration: 0.2) : ui }
}

/// Layout constants shared by every screen (docs/design-spec.md).
enum Metrics {
    /// Page margin: the same edge as inset lists, so every tab's text lines up.
    static let margin: CGFloat = 16
    /// Card padding: card text sits on the same 32 pt line as list rows.
    static let cardPadding: CGFloat = 16
    /// Cards match iOS 26 inset-grouped sections.
    static let cardRadius: CGFloat = 24
    static let stageRadius: CGFloat = 28
    static let buttonRadius: CGFloat = 14
    static let compactRadius: CGFloat = 12
    static let tileRadius: CGFloat = 10
}

/// One card: the same surface and shape as a list section on the other tabs.
struct CardModifier: ViewModifier {
    var tint = false

    func body(content: Content) -> some View {
        content
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint ? Palette.surface2 : Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

/// The dusk "stage": the Tonight card.
struct StageModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.stageCard, in: RoundedRectangle(cornerRadius: Metrics.stageRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.stageRadius, style: .continuous).strokeBorder(Palette.stageLine, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func card(tint: Bool = false) -> some View { modifier(CardModifier(tint: tint)) }
    /// The light-mode hero: a card with a little more height.
    func heroCard() -> some View {
        padding(.vertical, 4).modifier(CardModifier())
    }
    func stage() -> some View { modifier(StageModifier()) }

    /// Lists and forms on the brand surfaces (not iOS's neutral grays), 16 pt line.
    func barrierList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
    }

    /// For a list's sections: rows on the brand surface.
    func rows() -> some View { listRowBackground(Palette.surface) }
}

// MARK: - Text

struct Kicker: View {
    var text: String
    var color: Color = Palette.ink3

    init(_ text: String, color: Color = Palette.ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

struct SectionTitle: View {
    var title: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.barrierH2).foregroundStyle(Palette.ink)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Buttons (rounded rectangles, never pills)

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Palette.cta

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.onCta)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(fill.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var compact = false
    /// A fixed width, so a row of buttons lines up (Done next to Start).
    var width: CGFloat? = nil
    /// A square icon button (the "…" next to Done), the same height as its neighbors.
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        let h: CGFloat = compact ? 40 : 52
        configuration.label
            .font((compact ? Font.subheadline : .body).weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(minWidth: square ? h : width, minHeight: h)
            .padding(.horizontal, (square || width != nil) ? 0 : (compact ? 14 : 18))
            .background(Palette.fill.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: compact ? Metrics.compactRadius : Metrics.buttonRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Switches in sage: calm "on", and readable against the white thumb in dusk mode.
struct SageToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(Palette.ok)
    }
}

/// Text-only actions: "Not now", "Undo", "Skip". A 44 pt target, quiet ink.
struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.ink3)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line2, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Chips

struct Chip: View {
    var title: String
    var selected: Bool
    var hue: Hue?
    /// A trailing "plus" or "checkmark", for chips that add.
    var symbol: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let hue {
                    Circle().fill(Palette.hue(hue)).frame(width: 8, height: 8)
                }
                Text(title)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selected ? Palette.ink : Palette.ink3)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 40)
            .background(selected ? Palette.selected : Palette.fill, in: RoundedRectangle(cornerRadius: Metrics.compactRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.compactRadius, style: .continuous).strokeBorder(selected ? Palette.ink : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wraps children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Bits

struct HueDot: View {
    var hue: Hue?
    var size: CGFloat = 10
    var hollow = false

    var body: some View {
        Circle()
            .fill(hollow ? Color.clear : Palette.hue(hue))
            .overlay(Circle().strokeBorder(Palette.hue(hue), lineWidth: hollow ? 1.6 : 0))
            .frame(width: size, height: size)
    }
}

/// The evidence behind a note: one quiet "Sources" link that opens to the list.
/// There for trust, out of the way of reading.
struct SourcesView: View {
    var sources: [Source]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Motion.ui) { open.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.book.closed").font(.system(size: 10, weight: .semibold))
                    Text(sources.count == 1 ? "Source" : "Sources")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.ink3)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide sources" : "Show \(sources.count) sources")
            if open {
                links.transition(.opacity)
            }
        }
    }

    private var links: some View {
        FlowLayout(spacing: 10) {
            ForEach(sources) { s in
                if let url = URL(string: s.url) {
                    Link(destination: url) {
                        HStack(spacing: 3) {
                            Text(s.label)
                            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                        }
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                    }
                    .accessibilityLabel("Source: \(s.label)")
                }
            }
        }
    }
}

struct ToastView: View {
    var toast: Toast
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.text).font(.subheadline.weight(.medium))
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    dismiss()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.hue(.clay))
            }
        }
        .foregroundStyle(Palette.bg)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Formatting

extension ClockTime {
    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    init(date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(c.hour ?? 0, c.minute ?? 0)
    }

    var formatted: String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

extension Day {
    /// "Thursday, October 9"
    var long: String { date().formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    /// "Oct 9"
    var short: String { date().formatted(.dateTime.month(.abbreviated).day()) }
    /// "Thu"
    var weekdayShort: String { date().formatted(.dateTime.weekday(.abbreviated)) }
    /// "T"
    var weekdayLetter: String { date().formatted(.dateTime.weekday(.narrow)) }

    init(date: Date) { self = Day.of(date) }

    func relative(to today: Day, evening: Bool = true) -> String {
        let n = today.days(to: self)
        switch n {
        case 0: return evening ? "tonight" : "today"
        case 1: return evening ? "tomorrow night" : "tomorrow"
        case -1: return evening ? "last night" : "yesterday"
        case 2...6: return date().formatted(.dateTime.weekday(.wide))
        default: return short
        }
    }
}

extension View {
    /// What every presented screen needs: the model and the clay tint
    /// (sheets don't inherit the tint, and toggles would turn green).
    func barrier(_ model: AppModel) -> some View {
        environment(model)
            .tint(Palette.ink)
            .toggleStyle(SageToggleStyle())
            .presentationBackground(Palette.bg)
    }
}

// MARK: - Routine names and symbols

extension Slot {
    /// Outline symbol for rows.
    var symbol: String {
        switch self {
        case .am: return "sun.max"
        case .pm: return "moon"
        case .body, .body2: return "drop.halffull"
        }
    }

    /// Filled symbol for the big card.
    var fillSymbol: String {
        switch self {
        case .am: return "sun.max.fill"
        case .pm: return "moon.fill"
        case .body, .body2: return "drop.halffull"
        }
    }

    /// "Tonight", "This morning", or the body routine's cue ("After shower").
    func when(_ sp: SlotPlan) -> String {
        switch self {
        case .am: return "This morning"
        case .pm: return "Tonight"
        case .body, .body2: return (sp.cue ?? "").isEmpty ? "Today" : sp.cue!
        }
    }

    /// "Not tonight", "Not this morning", "Not today".
    var notNow: String {
        switch self {
        case .am: return "Not this morning"
        case .pm: return "Not tonight"
        case .body, .body2: return "Not today"
        }
    }

    /// The routine's name in the app ("Evening", "Morning", "Back").
    func name(_ plan: Plan) -> String {
        self.isBody ? plan.shortName(self) : title
    }

    /// Whether this routine's screens wear the dusk look.
    func isDusk(_ sp: SlotPlan) -> Bool {
        switch self {
        case .pm: return true
        case .am: return false
        case .body, .body2: return sp.time.hour >= 17 || sp.time.hour < dayRolloverHour
        }
    }
}
