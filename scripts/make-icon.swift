// Renders the Tracky app icon into an .iconset folder. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)
    ctx.interpolationQuality = .high

    // macOS icon grid: 824pt squircle centred in a 1024 canvas.
    let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: hex(0, 0.35))
    ctx.addPath(squircle); ctx.setFillColor(hex(0x111116)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [hex(0x2C2C36), hex(0x0C0C10)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.addPath(squircle); ctx.setStrokeColor(hex(0xFFFFFF, 0.12)); ctx.setLineWidth(5); ctx.strokePath()
    ctx.restoreGState()

    let c = CGPoint(x: 512, y: 512), r: CGFloat = 250, lw: CGFloat = 66

    ctx.setStrokeColor(hex(0xFFFFFF, 0.09)); ctx.setLineWidth(lw)
    ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()

    // 270° arc from 12 o'clock clockwise to 9 o'clock, filled with the brand gradient.
    let arc = CGMutablePath()
    arc.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: -.pi, clockwise: true)
    let stroked = arc.copy(strokingWithWidth: lw, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState()
    ctx.addPath(stroked); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [hex(0xFFB547), hex(0xFF6B4A), hex(0xFF3D6E)] as CFArray,
                       locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 700, y: 800), end: CGPoint(x: 280, y: 300),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Glowing playhead at the end of the arc.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 44 * s, color: hex(0xFF4D6A, 0.95))
    ctx.setFillColor(hex(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: c.x - r - 48, y: c.y - 48, width: 96, height: 96))
    ctx.restoreGState()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

// Stops at 512px: the 1024px variant alone would add ~0.5 MB for a menu bar app that's rarely seen in Finder.
for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x")] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
