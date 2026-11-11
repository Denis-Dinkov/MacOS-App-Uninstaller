// Renders the app icon: `swift tools/make_icon.swift <output.png>` (1024x1024).
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r, green: g, blue: b, alpha: a)
}

// Rounded tile following the macOS icon grid (824pt body inside a 1024pt canvas).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35).cgColor)
color(0.1, 0.08, 0.25).setFill()
tilePath.fill()
ctx.restoreGState()

ctx.saveGState()
tilePath.addClip()
NSGradient(colors: [color(0.05, 0.21, 0.36), color(0.21, 0.09, 0.34), color(0.09, 0.07, 0.24)])!
    .draw(in: tile, angle: 45)
// Soft glow behind the badge.
NSGradient(colors: [color(1.0, 0.36, 0.56, 0.45), color(1.0, 0.36, 0.56, 0)])!
    .draw(in: NSBezierPath(ovalIn: tile.insetBy(dx: 40, dy: 40)), relativeCenterPosition: .zero)
ctx.restoreGState()

// Gradient badge.
let badge = NSRect(x: 262, y: 262, width: 500, height: 500)
let badgePath = NSBezierPath(ovalIn: badge)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: color(1.0, 0.36, 0.56, 0.7).cgColor)
color(1.0, 0.36, 0.56).setFill()
badgePath.fill()
ctx.restoreGState()
NSGradient(colors: [color(1.0, 0.62, 0.38), color(1.0, 0.36, 0.56)])!.draw(in: badgePath, angle: 45)
color(1, 1, 1, 0.35).setStroke()
let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 22, dy: 22))
ring.lineWidth = 5
ring.stroke()

// White sparkles glyph.
let config = NSImage.SymbolConfiguration(pointSize: 250, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
    .withSymbolConfiguration(config)
{
    let s = symbol.size
    symbol.draw(in: NSRect(x: 512 - s.width / 2, y: 512 - s.height / 2, width: s.width, height: s.height))
}

NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
