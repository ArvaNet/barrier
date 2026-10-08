import Foundation

// Calm, cumulative milestones. Nothing resets, nothing is lost by missing a night.

public struct Milestone: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var body: String
    public var symbol: String // SF Symbol name
}

public enum Milestones {
    public static func reached(_ state: AppState, today: Day) -> [Milestone] {
        var out: [Milestone] = []
        let st = Engine.stats(state, today: today)
        let nights = st.nightsDone
        let daysIn = state.plan.createdAt.days(to: today) + 1

        if nights >= 1 {
            out.append(Milestone(id: "night-1", title: "First night done", body: "The hardest one. Everything from here is repetition.", symbol: "moon.stars"))
        }
        let rings = Engine.rings(state, today: today)
        if state.plan.pm.length >= 3, rings.dropLast().contains(where: { $0.segments.allSatisfy(\.done) }) {
            out.append(Milestone(id: "cycle-1", title: "A full cycle", body: "Every night of the rotation, start to finish. Your first ring is closed.", symbol: "circle.circle"))
        }
        for n in [7, 14, 28, 50, 100, 200, 365] where nights >= n {
            out.append(Milestone(id: "nights-\(n)", title: "\(n) nights", body: nightsCopy(n), symbol: "sparkles"))
        }
        for w in [4, 8, 12] where daysIn >= w * 7 {
            out.append(Milestone(id: "weeks-\(w)", title: "\(w) weeks in", body: weeksCopy(w), symbol: "calendar"))
        }
        if state.photos.count >= 2 {
            out.append(Milestone(id: "photos-2", title: "Before and after, unlocked", body: "Two photos means you can compare them side by side in Progress.", symbol: "photo.on.rectangle"))
        }
        return out
    }

    /// The newest milestone the user hasn't seen yet.
    public static func unseen(_ state: AppState, today: Day) -> Milestone? {
        reached(state, today: today).last { !state.milestonesSeen.contains($0.id) }
    }

    static func nightsCopy(_ n: Int) -> String {
        switch n {
        case 7: return "A week of nights. This is where a routine starts to feel like yours."
        case 14: return "Two weeks of looking after your skin. Quietly impressive."
        case 28: return "Four weeks of nights. That’s real consistency."
        case 50: return "Fifty nights. Nobody gets here by accident."
        case 100: return "A hundred nights. This is just what you do now."
        default: return "\(n) nights and counting."
        }
    }

    static func weeksCopy(_ w: Int) -> String {
        switch w {
        case 4: return "Many treatments start showing around weeks 4 to 8. A good week for a comparison photo."
        case 8: return "Eight weeks. If your dermatologist asked for an update, your report is ready."
        default: return "Twelve weeks: a common point to judge how a treatment is going."
        }
    }
}
