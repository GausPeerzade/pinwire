// Draws the Pinwire app icon: a taut wire across a deep teal square, with
// a note and a picture pinned to it by two round push pins.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func shadow(_ alpha: CGFloat, blur: CGFloat, y: CGFloat) {
    let s = NSShadow()
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.set()
}

// Body, following the macOS icon grid: 824pt square, 100pt margin.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
shadow(0.35, blur: 26, y: -12)
color(14, 40, 48).setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()
NSGradient(colors: [color(10, 34, 44), color(18, 92, 98), color(40, 150, 140)],
           atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: 70)

// The wire: straight and taut, slightly rising to the right.
func wireY(_ x: CGFloat) -> CGFloat { 688 + (x - 512) * 0.06 }
let wire = NSBezierPath()
wire.move(to: NSPoint(x: 60, y: wireY(60)))
wire.line(to: NSPoint(x: 964, y: wireY(964)))
ctx.saveGState()
shadow(0.45, blur: 8, y: -5)
wire.lineWidth = 9
color(226, 236, 236).setStroke()
wire.stroke()
ctx.restoreGState()

/// A card hanging from a pin near its top, rotated about the pin.
func card(pinX: CGFloat, width: CGFloat, height: CGFloat, angle: CGFloat, content: (NSRect) -> Void) {
    let pin = NSPoint(x: pinX, y: wireY(pinX))
    ctx.saveGState()
    ctx.translateBy(x: pin.x, y: pin.y)
    ctx.rotate(by: angle * .pi / 180)
    let rect = NSRect(x: -width / 2, y: -height + 26, width: width, height: height)
    let paper = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)
    ctx.saveGState()
    shadow(0.42, blur: 30, y: -16)
    color(250, 249, 245).setFill()
    paper.fill()
    ctx.restoreGState()
    ctx.saveGState()
    paper.addClip()
    content(rect)
    ctx.restoreGState()
    ctx.restoreGState()

    // The push pin: a glossy coral head over its own shadow.
    ctx.saveGState()
    shadow(0.5, blur: 10, y: -7)
    let head = NSRect(x: pin.x - 34, y: pin.y - 34, width: 68, height: 68)
    NSGradient(colors: [color(255, 140, 110), color(232, 70, 60)])!
        .draw(in: NSBezierPath(ovalIn: head), relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
    ctx.restoreGState()
    color(255, 255, 255, 0.75).setFill()
    NSBezierPath(ovalIn: NSRect(x: pin.x - 18, y: pin.y + 4, width: 18, height: 13)).fill()
}

// A note: lines of text, the copied item.
card(pinX: 360, width: 300, height: 360, angle: 4) { r in
    color(40, 52, 58, 0.85).setFill()
    let widths: [CGFloat] = [0.78, 0.62, 0.84, 0.5, 0.7]
    for (i, w) in widths.enumerated() {
        let y = r.maxY - 92 - CGFloat(i) * 46
        NSBezierPath(roundedRect: NSRect(x: r.minX + 40, y: y, width: (r.width - 80) * w, height: 18),
                     xRadius: 9, yRadius: 9).fill()
    }
}

// A picture: a small landscape, the screenshot.
card(pinX: 664, width: 316, height: 300, angle: -5) { r in
    let photo = r.insetBy(dx: 22, dy: 22).offsetBy(dx: 0, dy: -4)
    NSBezierPath(roundedRect: photo, xRadius: 12, yRadius: 12).addClip()
    NSGradient(colors: [color(255, 200, 150), color(150, 205, 230)])!.draw(in: photo, angle: 90)
    color(255, 240, 200).setFill()
    NSBezierPath(ovalIn: NSRect(x: photo.maxX - 92, y: photo.maxY - 104, width: 52, height: 52)).fill()
    let hills = NSBezierPath()
    hills.move(to: NSPoint(x: photo.minX, y: photo.minY))
    hills.line(to: NSPoint(x: photo.minX, y: photo.minY + 70))
    hills.curve(to: NSPoint(x: photo.midX, y: photo.minY + 90),
                controlPoint1: NSPoint(x: photo.minX + 60, y: photo.minY + 130),
                controlPoint2: NSPoint(x: photo.midX - 50, y: photo.minY + 120))
    hills.curve(to: NSPoint(x: photo.maxX, y: photo.minY + 110),
                controlPoint1: NSPoint(x: photo.midX + 60, y: photo.minY + 60),
                controlPoint2: NSPoint(x: photo.maxX - 40, y: photo.minY + 140))
    hills.line(to: NSPoint(x: photo.maxX, y: photo.minY))
    hills.close()
    color(30, 120, 110).setFill()
    hills.fill()
}

// Soft light from the top.
NSGradient(colors: [color(255, 255, 255, 0.10), color(255, 255, 255, 0)])!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

// Thin inner edge.
let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
edge.lineWidth = 3
color(255, 255, 255, 0.14).setStroke()
edge.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
