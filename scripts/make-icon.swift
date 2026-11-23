// Renders the Tracky app icon into an .iconset folder.
// Usage: swiftc -O scripts/make-icon.swift -o make-icon && ./make-icon <out.iconset>
//
// A flat stopwatch on paper: ink dial and crown, a vermilion wedge set to 45 minutes, a centre knob.
// No gradients or glow. Flat colour also keeps the PNGs tiny.
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

    // macOS icon grid: 824pt tile centred in a 1024 canvas, with the standard soft drop shadow.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 20 * s, color: hex(0, 0.28))
    ctx.addPath(tile); ctx.setFillColor(hex(0xF3EFE6)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(tile); ctx.setStrokeColor(hex(0x000000, 0.10)); ctx.setLineWidth(4); ctx.strokePath()

    let c = CGPoint(x: 512, y: 488)
    let ink = hex(0x1A1A1A)

    // Stopwatch crown and stem.
    ctx.setFillColor(ink)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 462, y: 812, width: 100, height: 46), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.fillPath()
    ctx.fill(CGRect(x: 494, y: 770, width: 36, height: 50))

    // Vermilion wedge, 12 o'clock clockwise to 9 o'clock (45 minutes).
    ctx.move(to: c)
    ctx.addArc(center: c, radius: 222, startAngle: .pi / 2, endAngle: -.pi, clockwise: true)
    ctx.closePath()
    ctx.setFillColor(hex(0xDB4527)); ctx.fillPath()

    // Ink dial ring.
    ctx.setStrokeColor(ink); ctx.setLineWidth(42)
    ctx.addEllipse(in: CGRect(x: c.x - 282, y: c.y - 282, width: 564, height: 564)); ctx.strokePath()

    // Centre knob.
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: c.x - 44, y: c.y - 44, width: 88, height: 88))

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
