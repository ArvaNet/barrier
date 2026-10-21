import BarrierCore
import UIKit

/// Stand-in progress photos for demo mode (screenshots): soft skin texture with
/// spots that fade from the first photo of an area to the last. Abstract on
/// purpose; never shown outside `-demo`.
enum DemoPhotos {
    static func ensure(_ photos: [PhotoMeta], in store: PhotoStore) {
        for area in Area.allCases {
            let list = photos.filter { $0.place == area && $0.id.hasPrefix("demo-") }.sorted { $0.at < $1.at }
            for (i, m) in list.enumerated() where store.image(m.id) == nil {
                // 1 on the first photo, down to 0.3 on the last.
                let severity = list.count > 1 ? 1 - 0.7 * Double(i) / Double(list.count - 1) : 1
                try? store.save(draw(area: area, severity: severity, shift: i), id: m.id)
            }
        }
    }

    static func draw(area: Area, severity: Double, shift: Int) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let tones: [UIColor] = area == .face
                ? [UIColor(red: 0.94, green: 0.80, blue: 0.70, alpha: 1), UIColor(red: 0.80, green: 0.62, blue: 0.52, alpha: 1)]
                : [UIColor(red: 0.88, green: 0.71, blue: 0.60, alpha: 1), UIColor(red: 0.72, green: 0.54, blue: 0.44, alpha: 1)]
            let skin = CGGradient(colorsSpace: space, colors: tones.map(\.cgColor) as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(skin, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            // Window light from the top left, a touch different each time.
            let light = CGGradient(colorsSpace: space, colors: [UIColor(white: 1, alpha: 0.28).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            let lx = 220 + CGFloat(shift % 3) * 30
            cg.drawRadialGradient(light, startCenter: CGPoint(x: lx, y: 260), startRadius: 0, endCenter: CGPoint(x: lx, y: 260), endRadius: 760, options: [])

            // Spots sit in the same places in every photo of an area, so the change reads.
            var rng = SeededGenerator(seed: area == .face ? 41 : 97)
            for _ in 0..<1400 {
                let p = CGPoint(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng))
                cg.setFillColor(UIColor(red: 0.45, green: 0.3, blue: 0.25, alpha: 0.06).cgColor)
                cg.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 3, height: 3))
            }
            for i in 0..<46 {
                let p = CGPoint(x: .random(in: 80...(size.width - 80), using: &rng), y: .random(in: 120...(size.height - 120), using: &rng))
                let r = CGFloat.random(in: 12...30, using: &rng)
                // Later photos: fewer and fainter.
                let shown = Double(i) / 46 < severity
                guard shown else { continue }
                let red = UIColor(red: 0.78, green: 0.36, blue: 0.33, alpha: 0.5 * severity)
                let blot = CGGradient(colorsSpace: space, colors: [red.cgColor, red.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                cg.drawRadialGradient(blot, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
            }
            for _ in 0..<28 {
                let p = CGPoint(x: .random(in: 120...(size.width - 120), using: &rng), y: .random(in: 200...(size.height - 160), using: &rng))
                let w = CGFloat.random(in: 7...16, using: &rng)
                cg.setFillColor(UIColor(red: 0.55, green: 0.38, blue: 0.32, alpha: 0.12 + 0.28 * severity).cgColor)
                cg.fillEllipse(in: CGRect(x: p.x, y: p.y, width: w, height: w * 0.8))
            }

            // A soft vignette.
            let edge = CGGradient(colorsSpace: space, colors: [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.22).cgColor] as CFArray, locations: [0.55, 1])!
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(edge, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.height * 0.75, options: [.drawsAfterEndLocation])
        }
    }
}

/// SplitMix64: the same picture every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
