import AppKit

let side = 1024
let image = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: image)!
NSGraphicsContext.current = context
context.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: side, height: side)
NSColor(calibratedRed: 0.035, green: 0.075, blue: 0.17, alpha: 1).setFill()
bounds.fill()
NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.19, blue: 0.36, alpha: 1),
    NSColor(calibratedRed: 0.025, green: 0.06, blue: 0.15, alpha: 1)
])!.draw(in: bounds, angle: 135)

let card = NSBezierPath(roundedRect: NSRect(x: 170, y: 190, width: 684, height: 644), xRadius: 76, yRadius: 76)
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.3)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 1).setFill()
card.fill()
NSShadow().set()

let coinRect = NSRect(x: 236, y: 514, width: 190, height: 190)
NSGradient(colors: [
    NSColor(calibratedRed: 0.15, green: 0.84, blue: 0.73, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.61, blue: 0.68, alpha: 1)
])!.draw(in: NSBezierPath(ovalIn: coinRect), angle: 135)

let currency = NSAttributedString(string: "$", attributes: [
    .font: NSFont.systemFont(ofSize: 142, weight: .bold),
    .foregroundColor: NSColor.white
])
let currencySize = currency.size()
currency.draw(at: NSPoint(x: coinRect.midX - currencySize.width / 2,
                          y: coinRect.midY - currencySize.height / 2 - 4))

func roundedBar(_ rect: NSRect, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
}

let ink = NSColor(calibratedRed: 0.14, green: 0.22, blue: 0.35, alpha: 1)
roundedBar(NSRect(x: 480, y: 626, width: 250, height: 34), color: ink)
roundedBar(NSRect(x: 480, y: 562, width: 178, height: 22), color: ink.withAlphaComponent(0.22))

roundedBar(NSRect(x: 248, y: 390, width: 528, height: 42), color: ink.withAlphaComponent(0.12))
roundedBar(NSRect(x: 248, y: 390, width: 365, height: 42),
           color: NSColor(calibratedRed: 0.08, green: 0.67, blue: 0.65, alpha: 1))

roundedBar(NSRect(x: 248, y: 304, width: 230, height: 20), color: ink.withAlphaComponent(0.22))
roundedBar(NSRect(x: 248, y: 264, width: 146, height: 20), color: ink.withAlphaComponent(0.12))

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments.dropFirst().first ?? "AIUsage-master.png"
let png = image.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
