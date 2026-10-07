// Renders every image in the README, in light and dark:
//   hero-*.png   headline and the wire hanging under the menu bar, with a
//                screenshot, a note, a link, a colour and a file pinned to it
//   demo-*.gif   text is selected and copied, and it is pinned to the wire;
//                later the pointer rests in the menu bar, the wire comes down
//                and a click copies an older item again
//   bento-*.png  six features as tiles with SF Symbols
// Usage: swift scripts/make-readme-art.swift docs/
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.dropFirst().first ?? "docs"

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// MARK: Themes

struct Theme {
    let name: String
    let page: NSColor          // README background behind everything
    let ink: NSColor
    let secondaryInk: NSColor
    let accent: NSColor
    let wallpaper: [NSColor]
    let glow: NSColor
    let menuBar: NSColor
    let menuInk: NSColor
    let line: NSColor
    let glassFill: NSColor
    let edgeTop: NSColor
    let edgeBottom: NSColor
    let shadow: NSColor
    let tile: NSColor
    let tileInk: NSColor
    let window: NSColor
    let windowBar: NSColor
    let windowInk: NSColor
    let selection: NSColor
}

let light = Theme(
    name: "light",
    page: color(255, 255, 255), ink: color(29, 29, 31), secondaryInk: color(110, 110, 115),
    accent: color(14, 128, 120),
    wallpaper: [color(204, 234, 230), color(226, 232, 250), color(255, 228, 220)],
    glow: color(255, 255, 255, 0.35),
    menuBar: color(255, 255, 255, 0.55), menuInk: color(30, 32, 48, 0.5),
    line: color(120, 124, 145), glassFill: color(255, 255, 255, 0.5),
    edgeTop: color(255, 255, 255, 0.95), edgeBottom: color(255, 255, 255, 0.35),
    shadow: color(30, 50, 60, 0.22),
    tile: color(245, 245, 247), tileInk: color(29, 29, 31),
    window: color(255, 255, 255, 0.97), windowBar: color(238, 239, 243), windowInk: color(40, 42, 48),
    selection: color(178, 215, 255))

let dark = Theme(
    name: "dark",
    page: color(13, 17, 23), ink: color(245, 245, 247), secondaryInk: color(161, 161, 166),
    accent: color(72, 204, 188),
    wallpaper: [color(10, 34, 44), color(22, 50, 64), color(56, 38, 70)],
    glow: color(80, 200, 190, 0.18),
    menuBar: color(20, 20, 30, 0.55), menuInk: color(255, 255, 255, 0.5),
    line: color(150, 154, 175), glassFill: color(255, 255, 255, 0.12),
    edgeTop: color(255, 255, 255, 0.45), edgeBottom: color(255, 255, 255, 0.08),
    shadow: color(0, 0, 0, 0.5),
    tile: color(28, 28, 30), tileInk: color(245, 245, 247),
    window: color(38, 40, 48, 0.97), windowBar: color(50, 52, 62), windowInk: color(228, 230, 236),
    selection: color(46, 92, 160))

// MARK: Canvas

func makeBitmap(_ w: CGFloat, _ h: CGFloat, scale: CGFloat) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(_ rep: NSBitmapImageRep, scale: CGFloat, _ body: (CGContext) -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    body(ctx)
    NSGraphicsContext.restoreGraphicsState()
}

func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func shadow(_ t: Theme, _ alpha: CGFloat, blur: CGFloat, y: CGFloat) {
    let s = NSShadow()
    s.shadowColor = t.shadow.withAlphaComponent(t.shadow.alphaComponent * alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.set()
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
          tracking: CGFloat = 0, centerX: CGFloat, baselineY: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let s = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: tracking])
    s.draw(at: NSPoint(x: centerX - s.size().width / 2, y: baselineY + font.descender))
}

func leftText(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
              tracking: CGFloat = 0, x: CGFloat, baselineY: CGFloat, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    let s = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: tracking])
    s.draw(at: NSPoint(x: x, y: baselineY + font.descender))
}

func textWidth(_ string: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width
}

/// Word-wrapped text laid out from the top of the rect down.
func wrappedText(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, in rect: NSRect) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    style.lineSpacing = size * 0.18
    let s = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    let needed = s.boundingRect(with: NSSize(width: rect.width, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin]).height
    let h = min(needed, rect.height)
    s.draw(with: NSRect(x: rect.minX, y: rect.maxY - h, width: rect.width, height: h),
           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
}

func symbol(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

// MARK: What hangs on the wire

enum Content {
    case screenshot
    case note(String, source: String)
    case link(String, source: String)
    case swatch(NSColor, String)
    case file(String)
}

struct Item { let x: CGFloat; let w: CGFloat; let h: CGFloat; let tilt: CGFloat; let content: Content }

let coral = color(255, 107, 90)
let note = Content.note("Ship Pinwire 1.0 on Friday, then announce it on X.", source: "Notes")
let link = Content.link("github.com/GausPeerzade/pinwire", source: "Safari")

// MARK: The scene

/// A window where text is selected and copied with Command-C.
struct CopyWindow {
    var selection: CGFloat = 1   // 0...1 how much of the line is selected
    var keycap: CGFloat = 0      // 0...1 opacity of the shortcut badge
}

struct SceneState {
    var reveal: CGFloat = 1            // 0 tucked away, 1 down
    var swing: [CGFloat] = Array(repeating: 0, count: 8)
    var cursor: NSPoint? = nil
    var hover: Int? = nil
    var pressed: CGFloat = 0
    var copied: CGFloat = 0            // 0...1 opacity of the Copied label
    var shown = Int.max                // how many items are on the wire
    var arrival: CGFloat = 1           // 0...1 the newest item dropping onto the wire
    var window: CopyWindow? = nil
}

let windowLines = ["Notes from today\u{2019}s sync",
                   "Ship Pinwire 1.0 on Friday, then announce it on X.",
                   "Ask for the store screenshots."]

func windowRect(_ W: CGFloat) -> NSRect { NSRect(x: W * 0.25, y: 24, width: W * 0.5, height: 142) }

/// Where the selected line ends: the pointer finishes the selection there.
func selectionEnd(_ W: CGFloat) -> NSPoint {
    let r = windowRect(W)
    return NSPoint(x: r.minX + 22 + textWidth(windowLines[1], size: 13, weight: .regular), y: r.maxY - 70)
}

func drawWindow(_ ctx: CGContext, _ t: Theme, W: CGFloat, state w: CopyWindow) {
    let r = windowRect(W)
    let shape = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
    ctx.saveGState(); shadow(t, 1, blur: 24, y: -10)
    t.window.setFill(); shape.fill()
    ctx.restoreGState()
    ctx.saveGState()
    shape.addClip()
    t.windowBar.setFill()
    NSRect(x: r.minX, y: r.maxY - 28, width: r.width, height: 28).fill()
    for (i, c) in [color(255, 95, 87), color(254, 188, 46), color(40, 200, 64)].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 12 + CGFloat(i) * 17, y: r.maxY - 18, width: 9, height: 9)).fill()
    }
    ctx.restoreGState()

    let x = r.minX + 22
    let full = textWidth(windowLines[1], size: 13, weight: .regular)
    if w.selection > 0 {
        t.selection.setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 2, y: r.maxY - 76, width: (full + 4) * w.selection, height: 20),
                     xRadius: 3, yRadius: 3).fill()
    }
    leftText(windowLines[0], size: 13, weight: .semibold, color: t.windowInk, x: x, baselineY: r.maxY - 46)
    leftText(windowLines[1], size: 13, weight: .regular, color: t.windowInk, x: x, baselineY: r.maxY - 70)
    leftText(windowLines[2], size: 13, weight: .regular, color: t.windowInk.withAlphaComponent(0.6),
             x: x, baselineY: r.maxY - 94)

    if w.keycap > 0 {
        ctx.saveGState()
        ctx.setAlpha(w.keycap)
        let k = NSRect(x: r.maxX - 96, y: r.minY + 16, width: 76, height: 34)
        ctx.saveGState(); shadow(t, 0.8, blur: 8, y: -3)
        (t.name == "light" ? color(255, 255, 255) : color(64, 66, 78)).setFill()
        NSBezierPath(roundedRect: k, xRadius: 8, yRadius: 8).fill()
        ctx.restoreGState()
        t.windowInk.withAlphaComponent(0.25).setStroke()
        let edge = NSBezierPath(roundedRect: k.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        edge.lineWidth = 1; edge.stroke()
        text("\u{2318} C", size: 17, weight: .semibold, color: t.windowInk, centerX: k.midX, baselineY: k.midY - 6)
        ctx.restoreGState()
    }
}

func drawScene(_ ctx: CGContext, _ t: Theme, rect: NSRect, items: [Item], state: SceneState, cornerRadius: CGFloat) {
    ctx.saveGState()
    let W = rect.width, H = rect.height
    ctx.translateBy(x: rect.minX, y: rect.minY)
    let canvas = NSRect(x: 0, y: 0, width: W, height: H)
    NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius).addClip()

    NSGradient(colors: t.wallpaper, atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: canvas, angle: -35)
    NSGradient(colors: [t.glow, t.glow.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: W * 0.5, y: H * 0.45), radius: 0,
              toCenter: NSPoint(x: W * 0.5, y: H * 0.45), radius: W * 0.6, options: [])

    if let w = state.window { drawWindow(ctx, t, W: W, state: w) }

    let barH: CGFloat = 26
    // The wire lives under the menu bar and slides out from beneath it.
    let hidden: CGFloat = 260
    let dy = (1 - state.reveal) * hidden
    let top = H - barH - 20 + dy
    let sag: CGFloat = 22
    func lineY(_ x: CGFloat) -> CGFloat { let f = x / W; return top - 4 * sag * f * (1 - f) }

    ctx.saveGState()
    NSRect(x: 0, y: 0, width: W, height: H - barH).clip()
    let linePath = NSBezierPath()
    linePath.move(to: NSPoint(x: -10, y: top))
    let c = NSPoint(x: W / 2, y: top - 2 * sag)
    linePath.curve(to: NSPoint(x: W + 10, y: top),
                   controlPoint1: NSPoint(x: -10 + (c.x + 10) * 2 / 3, y: top + (c.y - top) * 2 / 3),
                   controlPoint2: NSPoint(x: W + 10 + (c.x - W - 10) * 2 / 3, y: top + (c.y - top) * 2 / 3))
    ctx.saveGState(); shadow(t, 0.8, blur: 3, y: -2)
    linePath.lineWidth = 1.8; t.line.setStroke(); linePath.stroke()
    ctx.restoreGState()

    for (i, f) in items.enumerated() where i < state.shown {
        let arriving = i == state.shown - 1 && state.arrival < 1
        let hover = state.hover == i
        let scale: CGFloat = hover ? (1.03 - 0.06 * state.pressed) : 1
        ctx.saveGState()
        if arriving { ctx.setAlpha(state.arrival) }
        ctx.translateBy(x: f.x, y: lineY(f.x) + 7 + (arriving ? (1 - state.arrival) * 46 : 0))
        ctx.rotate(by: (f.tilt + state.swing[i]) * .pi / 180)
        ctx.scaleBy(x: scale, y: scale)
        drawCard(ctx, t, w: f.w, h: f.h, content: f.content, lift: hover)
        if hover && state.copied > 0 {
            drawCopied(ctx, t, y: -f.h - 18, alpha: state.copied)
        }
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Menu bar on top of everything, with the pin in the status area.
    t.menuBar.setFill()
    NSRect(x: 0, y: H - barH, width: W, height: barH).fill()
    t.menuInk.setFill()
    NSBezierPath(ovalIn: NSRect(x: 18, y: H - barH / 2 - 5, width: 10, height: 10)).fill()
    for (i, w) in [CGFloat(46), 32, 28, 40, 34].enumerated() {
        let x = 42 + CGFloat(i) * 52
        NSBezierPath(roundedRect: NSRect(x: x, y: H - barH / 2 - 3.5, width: w, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
    }
    for i in 0..<3 {
        NSBezierPath(roundedRect: NSRect(x: W - 34 - CGFloat(i) * 30, y: H - barH / 2 - 5, width: 16, height: 10), xRadius: 3, yRadius: 3).fill()
    }
    if let pin = symbol("pin.fill", size: 11, color: t.menuInk.withAlphaComponent(0.9)) {
        pin.draw(in: NSRect(x: W - 34 - 3 * 30, y: H - barH / 2 - pin.size.height / 2,
                            width: pin.size.width, height: pin.size.height))
    }

    if let p = state.cursor { drawCursor(ctx, t, at: NSPoint(x: p.x, y: min(p.y, H - 1))) }
    ctx.restoreGState()
}

/// One item: the content in a glass frame, held by a clip at the top.
func drawCard(_ ctx: CGContext, _ t: Theme, w: CGFloat, h: CGFloat, content: Content, lift: Bool) {
    let radius: CGFloat = 16, inset: CGFloat = 4.5
    let frame = NSRect(x: -w / 2, y: -h, width: w, height: h)
    let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    ctx.saveGState(); shadow(t, lift ? 1.3 : 1, blur: lift ? 30 : 22, y: lift ? -16 : -12)
    t.glassFill.setFill(); path.fill()
    ctx.restoreGState()

    let photo = frame.insetBy(dx: inset, dy: inset)
    ctx.saveGState()
    NSBezierPath(roundedRect: photo, xRadius: radius - inset, yRadius: radius - inset).addClip()
    drawContent(content, photo)
    ctx.restoreGState()

    ctx.saveGState()
    let ring = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    ring.append(NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: radius - 1, yRadius: radius - 1))
    ring.windingRule = .evenOdd
    ring.addClip()
    NSGradient(colors: [t.edgeTop, t.edgeBottom])!.draw(in: frame, angle: -90)
    ctx.restoreGState()

    let clip = NSRect(x: -4.5, y: -15, width: 9, height: 25)
    let clipPath = NSBezierPath(roundedRect: clip, xRadius: 3.5, yRadius: 3.5)
    ctx.saveGState(); shadow(t, 0.9, blur: 3, y: -1.5)
    color(200, 200, 205).setFill(); clipPath.fill()
    ctx.restoreGState()
    NSGradient(colors: [color(178, 179, 186), color(238, 239, 243), color(209, 210, 216), color(158, 159, 166)],
               atLocations: [0, 0.35, 0.65, 1], colorSpace: .sRGB)!.draw(in: clipPath, angle: 0)
    color(30, 30, 40, 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: -2.5, y: -0.7, width: 5, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()
}

let paper = color(250, 249, 245)
let paperInk = color(33, 34, 38)
let paperFaint = color(120, 122, 128)

/// The footer of a paper card: what it is and the app it came from.
func drawFooter(_ r: NSRect, symbolName: String, source: String?) {
    if let s = symbol(symbolName, size: 9, color: paperFaint) {
        s.draw(in: NSRect(x: r.minX + 10, y: r.minY + 8, width: s.size.width, height: s.size.height))
    }
    if let source { leftText(source, size: 9, weight: .medium, color: paperFaint, x: r.minX + 25, baselineY: r.minY + 10) }
}

func drawContent(_ content: Content, _ r: NSRect) {
    switch content {
    case .screenshot:
        color(250, 250, 252).setFill(); r.fill()
        let bar = NSRect(x: r.minX, y: r.maxY - 18, width: r.width, height: 18)
        color(236, 237, 242).setFill(); bar.fill()
        for (i, c) in [color(255, 95, 87), color(254, 188, 46), color(40, 200, 64)].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: r.minX + 8 + CGFloat(i) * 10, y: bar.midY - 3, width: 6, height: 6)).fill()
        }
        NSGradient(colors: [color(255, 186, 140), color(130, 200, 225)])!
            .draw(in: NSRect(x: r.minX + 10, y: r.minY + 10, width: r.width * 0.42, height: bar.minY - r.minY - 20), angle: 90)
        color(214, 217, 226).setFill()
        for i in 0..<5 {
            let y = bar.minY - 18 - CGFloat(i) * 13
            if y < r.minY + 10 { break }
            NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.5 + 4, y: y, width: r.width * [0.4, 0.3, 0.36, 0.24, 0.32][i],
                                             height: 5), xRadius: 2.5, yRadius: 2.5).fill()
        }
    case .note(let s, let source):
        paper.setFill(); r.fill()
        wrappedText(s, size: 11.5, weight: .regular, color: paperInk,
                    in: NSRect(x: r.minX + 10, y: r.minY + 24, width: r.width - 20, height: r.height - 34))
        drawFooter(r, symbolName: "text.alignleft", source: source)
    case .link(let s, let source):
        paper.setFill(); r.fill()
        wrappedText(s, size: 11.5, weight: .medium, color: color(20, 100, 170),
                    in: NSRect(x: r.minX + 10, y: r.minY + 24, width: r.width - 20, height: r.height - 34))
        drawFooter(r, symbolName: "link", source: source)
    case .swatch(let c, let hex):
        paper.setFill(); r.fill()
        c.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX + 10, y: r.minY + 26, width: r.width - 20, height: r.height - 36),
                     xRadius: 7, yRadius: 7).fill()
        leftText(hex, size: 10, weight: .medium, color: paperFaint, x: r.minX + 10, baselineY: r.minY + 10, mono: true)
    case .file(let name):
        paper.setFill(); r.fill()
        let icon = NSWorkspace.shared.icon(for: .pdf)
        let side: CGFloat = 52
        icon.draw(in: NSRect(x: r.midX - side / 2, y: r.maxY - side - 10, width: side, height: side))
        text(name, size: 10.5, weight: .medium, color: paperInk, centerX: r.midX, baselineY: r.minY + 14)
    }
}

func drawCopied(_ ctx: CGContext, _ t: Theme, y: CGFloat, alpha: CGFloat) {
    let w: CGFloat = 84, h: CGFloat = 24
    let r = NSRect(x: -w / 2, y: y - h / 2 + (1 - alpha) * 4, width: w, height: h)
    let p = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.saveGState(); shadow(t, 0.8, blur: 10, y: -4)
    (t.name == "light" ? color(255, 255, 255, 0.92) : color(50, 50, 60, 0.92)).setFill(); p.fill()
    ctx.restoreGState()
    text("\u{2713}  Copied", size: 11.5, weight: .semibold, color: t.ink, centerX: 0, baselineY: r.midY - 4)
    ctx.restoreGState()
}

func drawCursor(_ ctx: CGContext, _ t: Theme, at p: NSPoint) {
    let a = NSBezierPath()
    a.move(to: p)
    a.line(to: NSPoint(x: p.x, y: p.y - 20))
    a.line(to: NSPoint(x: p.x + 5, y: p.y - 15.5))
    a.line(to: NSPoint(x: p.x + 8.6, y: p.y - 23.5))
    a.line(to: NSPoint(x: p.x + 11.8, y: p.y - 22.1))
    a.line(to: NSPoint(x: p.x + 8.2, y: p.y - 14.1))
    a.line(to: NSPoint(x: p.x + 14.5, y: p.y - 14.1))
    a.close()
    ctx.saveGState(); shadow(t, 0.9, blur: 3, y: -1.5)
    NSColor.black.setFill(); a.fill()
    ctx.restoreGState()
    a.lineWidth = 1.3; NSColor.white.setStroke(); a.stroke()
}

// MARK: Hero

func hero(_ t: Theme) {
    let W: CGFloat = 1200, H: CGFloat = 640, s: CGFloat = 2
    let rep = makeBitmap(W, H, scale: s)
    draw(rep, scale: s) { ctx in
        t.page.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        text("Pinwire", size: 84, weight: .semibold, color: t.ink, tracking: -2.4, centerX: W / 2, baselineY: H - 128)
        text("Everything you copy, pinned within reach.", size: 30, weight: .regular, color: t.secondaryInk,
             tracking: -0.4, centerX: W / 2, baselineY: H - 182)
        let items = [Item(x: 150, w: 196, h: 132, tilt: 2.5, content: .screenshot),
                     Item(x: 350, w: 176, h: 120, tilt: -1.5, content: note),
                     Item(x: 545, w: 180, h: 112, tilt: 2, content: link),
                     Item(x: 735, w: 150, h: 112, tilt: -2.5, content: .swatch(coral, "#FF6B5A")),
                     Item(x: 925, w: 160, h: 118, tilt: 1.8, content: .file("Invoice-0423.pdf"))]
        let scene = NSRect(x: 60, y: 40, width: W - 120, height: 330)
        ctx.saveGState(); shadow(t, 0.6, blur: 40, y: -18)
        t.page.setFill(); NSBezierPath(roundedRect: scene, xRadius: 26, yRadius: 26).fill()
        ctx.restoreGState()
        drawScene(ctx, t, rect: scene, items: items,
                  state: SceneState(cursor: NSPoint(x: 600, y: 120)), cornerRadius: 26)
    }
    savePNG(rep, "\(outDir)/hero-\(t.name).png")
}

// MARK: Demo loop

func easeInOut(_ x: CGFloat) -> CGFloat { let x = max(0, min(1, x)); return x * x * (3 - 2 * x) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { a + (b - a) * x }
func lerp(_ a: NSPoint, _ b: NSPoint, _ x: CGFloat) -> NSPoint { NSPoint(x: lerp(a.x, b.x, x), y: lerp(a.y, b.y, x)) }
func spring(_ d: CGFloat) -> CGFloat { 1 - exp(-7 * d) * cos(9 * d) }
func sway(_ d: CGFloat, _ amount: CGFloat) -> CGFloat { amount * exp(-2.6 * d) * sin(8.5 * d + 0.6) }

func demo(_ t: Theme) {
    let W: CGFloat = 960, H: CGFloat = 360, s: CGFloat = 1
    let fps: CGFloat = 20, duration: CGFloat = 7.4
    let items = [Item(x: 175, w: 180, h: 122, tilt: 2.5, content: .screenshot),
                 Item(x: 372, w: 170, h: 108, tilt: -1.5, content: link),
                 Item(x: 566, w: 140, h: 104, tilt: 2.2, content: .swatch(coral, "#FF6B5A")),
                 Item(x: 762, w: 178, h: 116, tilt: -2, content: note)]

    let lineStart = NSPoint(x: windowRect(W).minX + 22, y: selectionEnd(W).y)
    let lineEnd = selectionEnd(W)
    let edge = NSPoint(x: 430, y: H)
    let onLink = NSPoint(x: 382, y: 238)
    let away = NSPoint(x: 840, y: 70)

    let url = URL(fileURLWithPath: "\(outDir)/demo-\(t.name).gif")
    let count = Int(fps * duration)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps,
                                                      kCGImagePropertyGIFUnclampedDelayTime: 1 / fps]] as CFDictionary

    for i in 0..<count {
        let time = CGFloat(i) / fps
        var st = SceneState(reveal: 0)
        var window = CopyWindow()

        // Select a line of text, then press Command-C.
        window.selection = easeInOut((time - 0.15) / 0.6)
        if time >= 0.9 && time < 1.9 {
            window.keycap = min(1, (time - 0.9) / 0.12) * (time > 1.6 ? max(0, 1 - (time - 1.6) / 0.3) : 1)
        }
        st.window = window

        // The pointer drags across the line, waits, goes up to the menu bar,
        // picks an older item, then leaves.
        if time < 0.15 { st.cursor = lineStart }
        else if time < 0.75 { st.cursor = lerp(lineStart, lineEnd, easeInOut((time - 0.15) / 0.6)) }
        else if time < 3.1 { st.cursor = lineEnd }
        else if time < 3.9 { st.cursor = lerp(lineEnd, edge, easeInOut((time - 3.1) / 0.8)) }
        else if time < 4.3 { st.cursor = edge }
        else if time < 5.0 { st.cursor = lerp(edge, onLink, easeInOut((time - 4.3) / 0.7)) }
        else if time < 6.3 { st.cursor = onLink }
        else { st.cursor = lerp(onLink, away, easeInOut((time - 6.3) / 0.6)) }

        // The copy is pinned: the wire peeks down and the note drops on.
        st.shown = time < 1.55 ? 3 : 4
        if time >= 1.55 { st.arrival = easeInOut((time - 1.55) / 0.4) }
        if time >= 1.35 && time < 3.0 {
            st.reveal = spring(time - 1.35)
            if time >= 1.95 { st.swing[3] = sway(time - 1.95, 10) }
        } else if time >= 3.0 && time < 3.4 {
            st.reveal = 1 - easeInOut((time - 3.0) / 0.28)
        } else if time >= 4.2 && time < 6.75 {
            // Resting in the menu bar brings it down again.
            let d = time - 4.2
            st.reveal = spring(d)
            for k in 0..<4 { st.swing[k] = sway(max(0, d - 0.05 * CGFloat(k)), 8) * (k % 2 == 0 ? 1 : -1) }
        } else if time >= 6.75 {
            st.reveal = 1 - easeInOut((time - 6.75) / 0.28)
        }

        // Click the link copied earlier: it is on the clipboard again.
        if time >= 4.85 && time < 6.3 { st.hover = 1 }
        if time >= 5.25 && time < 5.45 { st.pressed = easeInOut((time - 5.25) / 0.1) * (1 - easeInOut((time - 5.35) / 0.1)) }
        if time >= 5.4 && time < 6.3 { st.copied = min(1, (time - 5.4) / 0.15) * (time > 6.1 ? max(0, 1 - (time - 6.1) / 0.2) : 1) }

        let rep = makeBitmap(W, H, scale: s)
        draw(rep, scale: s) { ctx in
            t.page.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
            drawScene(ctx, t, rect: NSRect(x: 0, y: 0, width: W, height: H), items: items, state: st, cornerRadius: 22)
        }
        CGImageDestinationAddImage(dest, rep.cgImage!, frameProps)
    }
    CGImageDestinationFinalize(dest)
}

// MARK: Bento

func bento(_ t: Theme) {
    let W: CGFloat = 1200, H: CGFloat = 640, s: CGFloat = 2, gap: CGFloat = 20
    let tiles: [(String, String, String)] = [
        ("doc.on.clipboard", "Copy anything.", "Text, links, files, images and colours are pinned as you copy."),
        ("cursorarrow.click", "Click to copy again.", "Every format comes back, not a plain-text copy."),
        ("camera.viewfinder", "Screenshots too.", "Pinned the instant you take them. Hold to mark up."),
        ("arrow.up.forward.app", "Drag to share.", "Drop into any app. Folders keep screenshots."),
        ("lock.shield", "Private by default.", "Passwords are skipped. Nothing leaves your Mac."),
        ("xmark.circle", "Let it go.", "Click the cross. Copies are deleted for good."),
    ]
    let rep = makeBitmap(W, H, scale: s)
    draw(rep, scale: s) { ctx in
        t.page.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        let tw = (W - gap * 4) / 3, th = (H - gap * 3) / 2
        for (i, tile) in tiles.enumerated() {
            let col = CGFloat(i % 3), row = CGFloat(1 - i / 3)
            let r = NSRect(x: gap + col * (tw + gap), y: gap + row * (th + gap), width: tw, height: th)
            t.tile.setFill()
            NSBezierPath(roundedRect: r, xRadius: 28, yRadius: 28).fill()
            if let sym = symbol(tile.0, size: 38, color: t.accent, weight: .regular) {
                sym.draw(in: NSRect(x: r.minX + 36, y: r.maxY - 40 - sym.size.height,
                                    width: sym.size.width, height: sym.size.height))
            }
            leftText(tile.1, size: 27, weight: .semibold, color: t.tileInk, tracking: -0.6,
                     x: r.minX + 36, baselineY: r.minY + 112)
            wrappedText(tile.2, size: 18, weight: .regular, color: t.secondaryInk,
                        in: NSRect(x: r.minX + 36, y: r.minY + 28, width: tw - 72, height: 64))
        }
    }
    savePNG(rep, "\(outDir)/bento-\(t.name).png")
}

for t in [light, dark] {
    hero(t)
    bento(t)
    demo(t)
}
