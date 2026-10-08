import BarrierCore
import SwiftUI

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    var tint = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint ? Palette.surface2 : Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if !tint {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(tint ? 0 : 0.04), radius: 12, y: 6)
    }
}

/// The dusk "stage": the Tonight card and the ritual live here.
struct StageModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.stage, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.stageLine, lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func card(padding: CGFloat = 18, tint: Bool = false) -> some View { modifier(CardModifier(padding: padding, tint: tint)) }
    func stage() -> some View { modifier(StageModifier()) }
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
    var fill: Color = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(hex: 0xFFFDF9))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(fill.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.subheadline : .body).weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(minHeight: compact ? 40 : 52)
            .padding(.horizontal, compact ? 14 : 18)
            .background(Palette.surface2.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let hue {
                    Circle().fill(Palette.hue(hue)).frame(width: 8, height: 8)
                }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(selected ? Palette.accentSoft : Palette.surface2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected ? Palette.accent : .clear, lineWidth: 1.2))
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

struct SourcesView: View {
    var sources: [Source]

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(sources) { s in
                if let url = URL(string: s.url) {
                    Link(s.label, destination: url)
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .underline()
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
