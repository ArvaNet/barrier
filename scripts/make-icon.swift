// Draws the Tendwell app icon (growth rings) as a 1024 × 1024 PNG with no alpha.
// Run: swift scripts/make-icon.swift Barrier/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Deep emerald, a touch lighter at the top: depth without a gloss.
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x12603F), rgb(0x0B3F2B)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

let c = CGPoint(x: 512, y: 472) // CoreGraphics y runs up: rings and dot together sit centered
let mint: UInt32 = 0x7FD8A8

// The rings: each week of care adds one. Outer is faintest.
ctx.setLineWidth(36)
ctx.setStrokeColor(rgb(mint, 0.30))
ctx.strokeEllipse(in: CGRect(x: c.x - 330, y: c.y - 330, width: 660, height: 660))
ctx.setStrokeColor(rgb(mint, 0.58))
ctx.strokeEllipse(in: CGRect(x: c.x - 222, y: c.y - 222, width: 444, height: 444))
// The heart: solid mint.
ctx.setFillColor(rgb(mint))
ctx.fillEllipse(in: CGRect(x: c.x - 116, y: c.y - 116, width: 232, height: 232))

// Tonight: a marigold dot on the outer ring, at the top, with a soft halo.
let dot = CGPoint(x: c.x, y: c.y + 330)
ctx.setFillColor(rgb(0xF5B83D, 0.22))
ctx.fillEllipse(in: CGRect(x: dot.x - 98, y: dot.y - 98, width: 196, height: 196))
ctx.setFillColor(rgb(0xF5B83D))
ctx.fillEllipse(in: CGRect(x: dot.x - 64, y: dot.y - 64, width: 128, height: 128))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
