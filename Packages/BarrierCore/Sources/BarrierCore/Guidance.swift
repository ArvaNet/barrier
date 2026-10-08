import Foundation

// Guidance shown in the app. Every line traces to docs/derm-facts.md, which was
// fact-checked against AAD, drug labels, DermNet, Cleveland Clinic and an NHS
// trust leaflet. Rules: hedge ("commonly", "many dermatologists"), never
// override the dermatologist, no claims the sources don't make.

public struct Source: Hashable, Sendable, Identifiable {
    public var label: String
    public var url: String
    public var id: String { url }

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}

public struct Note: Hashable, Sendable {
    public var title: String
    public var body: String
    public var sources: [Source]

    public init(title: String, body: String, sources: [Source]) {
        self.title = title
        self.body = body
        self.sources = sources
    }
}

public enum Guidance {
    public enum S {
        public static let aadRetinoid = Source(label: "AAD: retinoids and retinol", url: "https://www.aad.org/public/everyday-care/skin-care-secrets/anti-aging/retinoid-retinol")
        public static let aad20s = Source(label: "AAD: skin care in your 20s", url: "https://www.aad.org/public/everyday-care/skin-care-basics/care/skin-care-in-your-20s")
        public static let aadSunscreen = Source(label: "AAD: how to apply sunscreen", url: "https://www.aad.org/public/everyday-care/sun-protection/shade-clothing-sunscreen/how-to-apply-sunscreen")
        public static let aadAcneTreat = Source(label: "AAD: acne treatment", url: "https://www.aad.org/public/diseases/acne/derm-treat/treat")
        public static let aadExfoliate = Source(label: "AAD: exfoliating safely", url: "https://www.aad.org/public/everyday-care/skin-care-secrets/routine/safely-exfoliate-at-home")
        public static let aadPhotos = Source(label: "AAD: taking pictures of your skin", url: "https://www.aad.org/public/fad/digital-health/taking-pictures-skin")
        public static let aadGuideline = Source(label: "AAD: 2024 acne guidelines", url: "https://www.aad.org/news/updated-guidelines-acne-management")
        public static let ccRetinol = Source(label: "Cleveland Clinic: retinol", url: "https://my.clevelandclinic.org/health/treatments/23293-retinol")
        public static let dermnetRetinoids = Source(label: "DermNet: topical retinoids", url: "https://dermnetnz.org/topics/topical-retinoids")
        public static let nhsAdapalene = Source(label: "NHS trust: adapalene leaflet", url: "https://dchft.nhs.uk/leaflets/adapalene-gels-and-cream-differin-and-epiduo/")
        public static let tretLabel = Source(label: "Tretinoin 0.05% label (DailyMed)", url: "https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=357ed7c9-6ffa-45b8-94be-4d440f5a1c22&type=display")
        public static let bpoStudy = Source(label: "BPO and tretinoin stability (PubMed)", url: "https://pubmed.ncbi.nlm.nih.gov/9990414/")
        public static let bowe = Source(label: "Dr. Whitney Bowe: skin cycling", url: "https://drwhitneybowebeauty.com/blogs/derm-scribbles/skin-cycling-dr-bowes-viral-beauty-editor-approved-skincare-method")

        public static let all: [Source] = [aadRetinoid, aad20s, aadSunscreen, aadAcneTreat, aadExfoliate, aadPhotos, aadGuideline, ccRetinol, dermnetRetinoids, nhsAdapalene, tretLabel, bpoStudy, bowe]
    }

    public static let disclaimer = "Barrier helps you follow the routine your dermatologist gave you. It doesn’t diagnose or give medical advice, and your dermatologist’s instructions always come first."

    public static func conflict(_ id: ConflictID) -> Note {
        switch id {
        case .retinoidExfoliant:
            return Note(
                title: "Retinoid and exfoliant on the same night",
                body: "Both can irritate, so many dermatologists keep them on separate nights. If your dermatologist planned them together, carry on.",
                sources: [S.aadExfoliate, S.ccRetinol]
            )
        case .bpoTretinoin:
            return Note(
                title: "Benzoyl peroxide with tretinoin",
                body: "They’re often prescribed together, but some tretinoin products break down with benzoyl peroxide, so many people use them at different times of day. Use them the way your dermatologist told you.",
                sources: [S.aadGuideline, S.bpoStudy]
            )
        }
    }

    public static let irritation = Note(
        title: "When skin feels irritated",
        body: "If your skin feels raw, tight or stings, it’s common to pause the active for a few nights and use just a gentle cleanser and moisturizer until it calms, then restart less often. Check with your dermatologist about how to pause and restart.",
        sources: [S.tretLabel, S.nhsAdapalene, S.aadAcneTreat]
    )

    public static let callYourDerm = "Contact your dermatologist if burning feels severe, if you get swelling, blistering or crusting, or if irritation keeps getting worse instead of settling. If your face, lips or throat swell, or you have trouble breathing, get urgent medical help."

    public static let photoTips = Note(
        title: "Photos your dermatologist can use",
        body: "Same spot each time, bright window light, plain background, no makeup, no filters. Ask your dermatologist how often they’d like to see them.",
        sources: [S.aadPhotos]
    )

    public static let skinCycling = Note(
        title: "About skin cycling",
        body: "Skin cycling is a popular routine, not a medical treatment, and it may not fit a plan your dermatologist prescribed. If you have a prescription plan, follow that instead.",
        sources: [S.bowe]
    )

    public static let easeIn = Note(
        title: "Easing in",
        body: "Dermatologists commonly start a retinoid 2 to 3 nights a week for a couple of weeks, then add nights as skin allows. This is a common pattern, not a rule: set the weeks to match what your dermatologist said.",
        sources: [S.aadRetinoid, S.nhsAdapalene, S.ccRetinol]
    )

    /// "How's it going" note for a product on day `day` of use.
    public static func journey(kind: ProductKind, day: Int) -> Note? {
        let week = (day - 1) / 7 + 1
        switch kind {
        case .retinoid:
            if day <= 21 {
                return Note(title: "Week \(week): settling in",
                            body: "A little dryness, redness, peeling or mild stinging is common in the first few weeks and often settles within about 2 to 4 weeks. A few extra pimples early on can happen too.",
                            sources: [S.tretLabel, S.nhsAdapalene])
            }
            if day <= 56 {
                return Note(title: "Week \(week): the slow part",
                            body: "Most acne treatments take about 4 to 8 weeks before you notice fewer breakouts. Skin can look a little worse before it gets better.",
                            sources: [S.aadAcneTreat])
            }
            if day <= 90 {
                return Note(title: "Week \(week): around the check-in point",
                            body: "Tretinoin for acne is often judged at around 12 weeks. A good time for a comparison photo and a question list for your dermatologist.",
                            sources: [S.dermnetRetinoids, S.aadAcneTreat])
            }
            return Note(title: "Week \(week): the long game",
                        body: "For fine lines and sun damage, retinoids can take 3 to 6 months or longer. Consistency is the whole trick.",
                        sources: [S.tretLabel, S.dermnetRetinoids])
        case .treatment:
            guard day <= 56 else { return nil }
            return Note(title: "Week \(week)",
                        body: "Most acne treatments take about 4 to 8 weeks before you notice a difference, and clearing can take a few months. Rosacea treatments are often reassessed around 12 weeks.",
                        sources: [S.aadAcneTreat])
        default:
            return nil
        }
    }

    public struct Tip: Hashable, Sendable {
        public var id: String
        public var text: String
        public var source: Source?
        let needs: Set<ProductKind>
        let anyOf: Bool
    }

    public static let tips: [Tip] = [
        Tip(id: "dry", text: "Many dermatologists suggest waiting 20 to 30 minutes after washing before a retinoid. Damp skin can feel more irritated.", source: S.aad20s, needs: [.retinoid], anyOf: false),
        Tip(id: "pea", text: "A pea-sized amount commonly covers the whole face. More won’t work faster.", source: S.ccRetinol, needs: [.retinoid], anyOf: false),
        Tip(id: "sun", text: "Retinoids can make skin more sun-sensitive. Broad-spectrum SPF 30 or higher every morning.", source: S.aadSunscreen, needs: [.retinoid, .exfoliant], anyOf: true),
        Tip(id: "reapply", text: "Outdoors? Reapply sunscreen about every 2 hours, and after swimming or sweating.", source: S.aadSunscreen, needs: [.spf], anyOf: false),
        Tip(id: "moist", text: "Moisturizer before, after, or both? Dermatologists differ. Use the order yours gave you.", source: S.aadRetinoid, needs: [.retinoid, .moisturizer], anyOf: false),
        Tip(id: "one", text: "Add one new product at a time, so it’s clear what’s helping and what’s irritating.", source: nil, needs: [], anyOf: false),
        Tip(id: "slow", text: "Results usually take 4 to 8 weeks to show. The nights that feel like nothing is happening still count.", source: S.aadAcneTreat, needs: [.treatment, .retinoid], anyOf: true),
        Tip(id: "photo", text: "Photos beat memory. Same spot, window light, no makeup, and your dermatologist gets to see real progress.", source: S.aadPhotos, needs: [], anyOf: false),
        Tip(id: "exf", text: "Exfoliating on top of retinoids can mean more dryness. Keep them on separate nights unless your dermatologist says otherwise.", source: S.aadExfoliate, needs: [.exfoliant], anyOf: false),
    ]

    public static func tip(for kinds: Set<ProductKind>, dayNumber: Int) -> Tip {
        let pool = tips.filter { t in
            if t.needs.isEmpty { return true }
            return t.anyOf ? !t.needs.isDisjoint(with: kinds) : t.needs.isSubset(of: kinds)
        }
        let n = ((dayNumber % pool.count) + pool.count) % pool.count
        return pool[n]
    }
}
