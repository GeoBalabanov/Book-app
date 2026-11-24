// Renders the Lexi app icon (1024×1024 PNG): two paper index cards fanned on a
// warm ink background; the front card has a ruled header and a serif "L" over
// the gold marker the app uses for looked-up words.
// Usage (from ios/):
//   swift Tools/make_icon.swift Lexi/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//   swift Tools/make_icon.swift Lexi/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png dark
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let dark = args.count > 2 && args[2] == "dark"
let size: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: warm ink with a soft top light (opaque, full bleed; iOS masks the corners).
let bgTop = dark ? rgb(0x1a1714) : rgb(0x2b241d)
let bgBottom = dark ? rgb(0x0e0c0a) : rgb(0x17130f)
let gradient = NSGradient(starting: bgTop, ending: bgBottom)!
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

let paper = dark ? rgb(0x2a2621) : rgb(0xfbf8f1)
let paperBack = dark ? rgb(0x23201c) : rgb(0xefe8da)
let ink = dark ? rgb(0xede6d8) : rgb(0x221d17)
let rule = dark ? rgb(0xede6d8, 0.14) : rgb(0x785a3c, 0.22)
let muted = dark ? rgb(0x9a907f) : rgb(0x8b8174)
let marker = rgb(0xd6aa5a, dark ? 0.45 : 0.42)

let cardW: CGFloat = 640, cardH: CGFloat = 440
let center = CGPoint(x: size / 2, y: size / 2 - 6)

func card(rotation: CGFloat, offset: CGPoint, fill: NSColor, shadow: Bool, draw: ((CGRect) -> Void)? = nil) {
    ctx.saveGState()
    ctx.translateBy(x: center.x + offset.x, y: center.y + offset.y)
    ctx.rotate(by: rotation * .pi / 180)
    let rect = CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH)
    if shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 60, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    }
    let path = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill.cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    if let draw {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        draw(rect)
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

// Back card, fanned left.
card(rotation: 9, offset: CGPoint(x: -34, y: 30), fill: paperBack, shadow: true)

// Front card.
card(rotation: -4, offset: CGPoint(x: 20, y: -12), fill: paper, shadow: true) { r in
    // Faint grain.
    var seed: UInt64 = 7
    func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
    ctx.setFillColor((dark ? NSColor.white.withAlphaComponent(0.04) : rgb(0x735f4c, 0.07)).cgColor)
    for _ in 0..<9000 {
        let x = r.minX + CGFloat(next() % 10000) / 10000 * r.width
        let y = r.minY + CGFloat(next() % 10000) / 10000 * r.height
        ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
    }

    // Ruled header.
    let headerY = r.maxY - 92
    ctx.setFillColor(rule.cgColor)
    ctx.fill(CGRect(x: r.minX, y: headerY, width: r.width, height: 4))
    // Small-caps stand-in: two short rules in the header, like a label and "No. 1".
    ctx.setFillColor(muted.withAlphaComponent(0.55).cgColor)
    ctx.fill(CGRect(x: r.minX + 52, y: headerY + 38, width: 150, height: 14).insetBy(dx: 0, dy: 0))
    ctx.fill(CGRect(x: r.maxX - 52 - 70, y: headerY + 38, width: 70, height: 14))

    // Serif "L" over the gold marker.
    // New York (the system serif) via its design descriptor; it has no public PostScript name.
    let base = NSFont.systemFont(ofSize: 330, weight: .semibold)
    let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 330) } ?? base
    let text = NSAttributedString(string: "L", attributes: [.font: font, .foregroundColor: ink])
    let ts = text.size()
    let baseY = r.minY + 70
    let tx = r.midX - ts.width / 2 + 6
    // Marker: lower ~40% of the letter's x-height band, a bit wider than the glyph.
    ctx.setFillColor(marker.cgColor)
    ctx.fill(CGRect(x: tx - 36, y: baseY + 18, width: ts.width + 72, height: 96))
    text.draw(at: CGPoint(x: tx, y: baseY + font.descender + 10))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
