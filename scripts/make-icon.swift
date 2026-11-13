// Dessine l'icône de Dynamic Island Mac : un écran au dégradé violet et rose,
// et l'île noire ouverte en haut, avec sa pochette, son égaliseur et sa barre de lecture.
import AppKit

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Tuile arrondie, comme les icônes macOS.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.98, green: 0.42, blue: 0.52, alpha: 1),
                    NSColor(red: 0.55, green: 0.27, blue: 0.85, alpha: 1),
                    NSColor(red: 0.13, green: 0.10, blue: 0.38, alpha: 1)])!
    .draw(in: shape, angle: -70)

shape.addClip()

// Halo lumineux sous l'île.
NSGradient(starting: NSColor.white.withAlphaComponent(0.28), ending: NSColor.white.withAlphaComponent(0))!
    .draw(fromCenter: NSPoint(x: 512, y: 640), radius: 0, toCenter: NSPoint(x: 512, y: 640), radius: 420, options: [])

// L'île : forme d'encoche évasée en haut, arrondie en bas.
let islandRect = NSRect(x: 236, y: 540, width: 552, height: 384)
let flare: CGFloat = 30
let bottom: CGFloat = 110
let island = NSBezierPath()
island.move(to: NSPoint(x: islandRect.minX, y: islandRect.maxY))
island.curve(to: NSPoint(x: islandRect.minX + flare, y: islandRect.maxY - flare),
             controlPoint1: NSPoint(x: islandRect.minX + flare, y: islandRect.maxY),
             controlPoint2: NSPoint(x: islandRect.minX + flare, y: islandRect.maxY))
island.line(to: NSPoint(x: islandRect.minX + flare, y: islandRect.minY + bottom))
island.appendArc(withCenter: NSPoint(x: islandRect.minX + flare + bottom, y: islandRect.minY + bottom),
                 radius: bottom, startAngle: 180, endAngle: 270)
island.line(to: NSPoint(x: islandRect.maxX - flare - bottom, y: islandRect.minY))
island.appendArc(withCenter: NSPoint(x: islandRect.maxX - flare - bottom, y: islandRect.minY + bottom),
                 radius: bottom, startAngle: 270, endAngle: 360)
island.line(to: NSPoint(x: islandRect.maxX - flare, y: islandRect.maxY - flare))
island.curve(to: NSPoint(x: islandRect.maxX, y: islandRect.maxY),
             controlPoint1: NSPoint(x: islandRect.maxX - flare, y: islandRect.maxY),
             controlPoint2: NSPoint(x: islandRect.maxX - flare, y: islandRect.maxY))
island.close()

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
island.fill()
NSGraphicsContext.restoreGraphicsState()

// Pochette.
let art = NSRect(x: 310, y: 680, width: 150, height: 150)
let artPath = NSBezierPath(roundedRect: art, xRadius: 30, yRadius: 30)
NSGradient(starting: NSColor(red: 1.0, green: 0.48, blue: 0.55, alpha: 1),
           ending: NSColor(red: 0.45, green: 0.30, blue: 0.95, alpha: 1))!.draw(in: artPath, angle: -50)
NSColor.white.withAlphaComponent(0.9).setFill()
NSBezierPath(ovalIn: NSRect(x: art.midX - 28, y: art.midY - 28, width: 56, height: 56)).fill()

// Égaliseur.
let accent = NSColor(red: 1.0, green: 0.50, blue: 0.70, alpha: 1)
accent.setFill()
for (i, h) in [60.0, 115.0, 85.0, 135.0, 55.0].enumerated() {
    let x = 515 + CGFloat(i) * 40
    NSBezierPath(roundedRect: NSRect(x: x, y: 755 - h / 2, width: 22, height: h), xRadius: 11, yRadius: 11).fill()
}

// Barre de lecture.
NSColor.white.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: NSRect(x: 310, y: 625, width: 404, height: 16), xRadius: 8, yRadius: 8).fill()
accent.setFill()
NSBezierPath(roundedRect: NSRect(x: 310, y: 625, width: 175, height: 16), xRadius: 8, yRadius: 8).fill()

// Paroles sous l'île : la ligne chantée brille, les suivantes s'estompent.
let glow = NSShadow()
glow.shadowColor = NSColor.white.withAlphaComponent(0.8)
glow.shadowBlurRadius = 24
NSGraphicsContext.saveGraphicsState()
glow.set()
NSColor.white.withAlphaComponent(0.95).setFill()
NSBezierPath(roundedRect: NSRect(x: 292, y: 400, width: 440, height: 34), xRadius: 17, yRadius: 17).fill()
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.45).setFill()
NSBezierPath(roundedRect: NSRect(x: 342, y: 330, width: 340, height: 28), xRadius: 14, yRadius: 14).fill()
NSColor.white.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: NSRect(x: 382, y: 268, width: 260, height: 24), xRadius: 12, yRadius: 12).fill()

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
