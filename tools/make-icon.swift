// Renders the Screen Limiter icon: an indigo squircle, a time-budget ring
// (amber = used), and an hourglass. Usage:
//   swift tools/make-icon.swift <out-dir>
// Produces <out-dir>/AppIcon.iconset/*.png and <out-dir>/extension/{16,32,48,128}.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/icon")
let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Superellipse ("squircle") like Apple's icon shape.
func squircle(in r: CGRect, n: CGFloat = 4) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, c = CGPoint(x: r.midX, y: r.midY)
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = c.x + a * (ct >= 0 ? 1 : -1) * pow(abs(ct), 2 / n)
        let y = c.y + b * (st >= 0 ? 1 : -1) * pow(abs(st), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func renderMaster(shadow: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)
    let c = CGPoint(x: S / 2, y: S / 2 - 4)

    // Drop shadow (macOS icon grid style).
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(rgb(0x3634A3))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Background gradient.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [rgb(0x7D7AFF), rgb(0x4B48D6), rgb(0x2A2899)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: S / 2, y: body.maxY), end: CGPoint(x: S / 2, y: body.minY), options: [])
    // Soft top highlight.
    let glow = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S / 2, y: body.maxY - 40), startRadius: 0,
                           endCenter: CGPoint(x: S / 2, y: body.maxY - 40), endRadius: 560, options: [])
    ctx.restoreGState()

    // Budget ring: faint track + amber "used" arc starting at 12 o'clock, clockwise.
    let ringR: CGFloat = 300, ringW: CGFloat = 58
    ctx.setLineCap(.round)
    ctx.setLineWidth(ringW)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18))
    ctx.addArc(center: c, radius: ringR, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()

    let start = CGFloat.pi / 2
    let end = start - 2 * .pi * 0.72
    let arc = CGMutablePath()
    arc.addArc(center: c, radius: ringR, startAngle: start, endAngle: end, clockwise: true)
    let stroked = arc.copy(strokingWithWidth: ringW, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    let amber = CGGradient(colorsSpace: nil, colors: [rgb(0xFFD60A), rgb(0xFF9F0A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(amber, start: CGPoint(x: c.x, y: c.y + ringR + ringW), end: CGPoint(x: c.x, y: c.y - ringR - ringW),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Hourglass.
    let h: CGFloat = 150, w: CGFloat = 104, neck: CGFloat = 13
    let glass = CGMutablePath()
    glass.move(to: CGPoint(x: c.x - w, y: c.y + h))
    glass.addCurve(to: CGPoint(x: c.x - neck, y: c.y), control1: CGPoint(x: c.x - w, y: c.y + h * 0.42),
                   control2: CGPoint(x: c.x - neck, y: c.y + h * 0.22))
    glass.addCurve(to: CGPoint(x: c.x - w, y: c.y - h), control1: CGPoint(x: c.x - neck, y: c.y - h * 0.22),
                   control2: CGPoint(x: c.x - w, y: c.y - h * 0.42))
    glass.addLine(to: CGPoint(x: c.x + w, y: c.y - h))
    glass.addCurve(to: CGPoint(x: c.x + neck, y: c.y), control1: CGPoint(x: c.x + w, y: c.y - h * 0.42),
                   control2: CGPoint(x: c.x + neck, y: c.y - h * 0.22))
    glass.addCurve(to: CGPoint(x: c.x + w, y: c.y + h), control1: CGPoint(x: c.x + neck, y: c.y + h * 0.22),
                   control2: CGPoint(x: c.x + w, y: c.y + h * 0.42))
    glass.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x000000, 0.25))
    ctx.addPath(glass)
    ctx.setFillColor(rgb(0xFFFFFF, 0.95))
    ctx.fillPath()
    ctx.restoreGState()

    // Sand: a heap in the bottom bulb, a little left on top, and a stream.
    ctx.saveGState()
    ctx.addPath(glass)
    ctx.clip()
    ctx.setFillColor(rgb(0xFF9F0A))
    let heap = CGMutablePath()
    heap.move(to: CGPoint(x: c.x - w, y: c.y - h))
    heap.addLine(to: CGPoint(x: c.x - w, y: c.y - h * 0.62))
    heap.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y - h * 0.62), control: CGPoint(x: c.x, y: c.y - h * 0.18))
    heap.addLine(to: CGPoint(x: c.x + w, y: c.y - h))
    heap.closeSubpath()
    ctx.addPath(heap)
    ctx.fillPath()
    ctx.setFillColor(rgb(0xFFB340))
    let top = CGMutablePath()
    top.move(to: CGPoint(x: c.x - w * 0.5, y: c.y + h * 0.42))
    top.addQuadCurve(to: CGPoint(x: c.x + w * 0.5, y: c.y + h * 0.42), control: CGPoint(x: c.x, y: c.y + h * 0.5))
    top.addLine(to: CGPoint(x: c.x, y: c.y))
    top.closeSubpath()
    ctx.addPath(top)
    ctx.fillPath()
    ctx.fill(CGRect(x: c.x - 4, y: c.y - h * 0.5, width: 8, height: h * 0.5))
    ctx.restoreGState()

    // End caps (frame of the hourglass).
    ctx.setFillColor(rgb(0xFFFFFF))
    for y in [c.y + h, c.y - h] {
        let cap = CGRect(x: c.x - w - 22, y: y - 17, width: (w + 22) * 2, height: 34)
        ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 17, cornerHeight: 17, transform: nil))
        ctx.fillPath()
    }

    return ctx.makeImage()!
}

func resized(_ image: CGImage, to px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let appMaster = renderMaster(shadow: true)
let iconset = outDir.appending(path: "AppIcon.iconset")
for base in [16, 32, 128, 256, 512] {
    writePNG(resized(appMaster, to: base), to: iconset.appending(path: "icon_\(base)x\(base).png"))
    writePNG(resized(appMaster, to: base * 2), to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
writePNG(appMaster, to: outDir.appending(path: "AppIcon-1024.png"))

// Extension icons: no drop shadow, cropped tighter so they read at 16 px.
let flat = renderMaster(shadow: false)
let cropped = flat.cropping(to: CGRect(x: 88, y: 88, width: 848, height: 848))!
for px in [16, 32, 48, 128] {
    writePNG(resized(cropped, to: px), to: outDir.appending(path: "extension/\(px).png"))
}
print("Wrote icons to \(outDir.path)")
