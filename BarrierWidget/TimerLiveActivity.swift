import ActivityKit
import BarrierCore
import SwiftUI
import WidgetKit

/// The wait between steps, on the Lock Screen and in the Dynamic Island.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RitualTimerAttributes.self) { context in
            let hue = Hue(rawValue: context.attributes.hue) ?? .sage
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(hue.color).frame(width: 8, height: 8)
                        Text(context.attributes.title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(Palette.stageInk2)
                    }
                    Text(context.attributes.reason).font(.headline).foregroundStyle(Palette.stageInk)
                    Text("Next: \(context.state.nextStep)").font(.subheadline).foregroundStyle(Palette.stageInk2)
                }
                Spacer()
                Text(timerInterval: Self.range(context.state.endsAt), countsDown: true)
                    .font(Typeface.display(34, weight: 400))
                    .monospacedDigit()
                    .foregroundStyle(Palette.stageInk)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 104, alignment: .trailing)
            }
            .padding(18)
            .activityBackgroundTint(Palette.stage)
            .activitySystemActionForegroundColor(Palette.stageInk)
        } dynamicIsland: { context in
            let hue = Hue(rawValue: context.attributes.hue) ?? .sage
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.reason, systemImage: "hourglass")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Self.range(context.state.endsAt), countsDown: true)
                        .font(.title2.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Next: \(context.state.nextStep)").font(.subheadline).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Circle().fill(hue.color).frame(width: 10, height: 10)
            } compactTrailing: {
                Text(timerInterval: Self.range(context.state.endsAt), countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "hourglass").foregroundStyle(hue.color)
            }
        }
    }

    static func range(_ end: Date) -> ClosedRange<Date> {
        let now = Date()
        return now <= end ? now...end : end...end
    }
}
