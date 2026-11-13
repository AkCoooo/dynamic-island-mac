import AppKit

/// Logo de l'app pour la barre des menus : l'île vue de face, avec sa pochette et son égaliseur
/// découpés, et une ligne de paroles dessous. Image « modèle » : macOS la colore en noir ou en blanc
/// selon le fond de la barre des menus.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // L'île : évasée en haut, arrondie en bas.
            let island = CGMutablePath()
            let x0: CGFloat = 0.5, x1: CGFloat = 19.5, top: CGFloat = 2, bottom: CGFloat = 9.6
            let flare: CGFloat = 1.5, r: CGFloat = 3.6
            island.move(to: CGPoint(x: x0, y: top))
            island.addQuadCurve(to: CGPoint(x: x0 + flare, y: top + flare), control: CGPoint(x: x0 + flare, y: top))
            island.addLine(to: CGPoint(x: x0 + flare, y: bottom - r))
            island.addQuadCurve(to: CGPoint(x: x0 + flare + r, y: bottom), control: CGPoint(x: x0 + flare, y: bottom))
            island.addLine(to: CGPoint(x: x1 - flare - r, y: bottom))
            island.addQuadCurve(to: CGPoint(x: x1 - flare, y: bottom - r), control: CGPoint(x: x1 - flare, y: bottom))
            island.addLine(to: CGPoint(x: x1 - flare, y: top + flare))
            island.addQuadCurve(to: CGPoint(x: x1, y: top), control: CGPoint(x: x1 - flare, y: top))
            island.closeSubpath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(island)
            ctx.fillPath()

            // Pochette et égaliseur, découpés dans l'île.
            ctx.setBlendMode(.clear)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 4.3, y: 4.0, width: 3.8, height: 3.8),
                               cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
            ctx.fillPath()
            for (i, h) in [1.8, 3.6, 2.6].enumerated() {
                let bx = 11.6 + CGFloat(i) * 1.9
                ctx.addPath(CGPath(roundedRect: CGRect(x: bx, y: 5.9 - h / 2, width: 1.1, height: h),
                                   cornerWidth: 0.55, cornerHeight: 0.55, transform: nil))
                ctx.fillPath()
            }

            // Ligne de paroles sous l'île.
            ctx.setBlendMode(.normal)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 5.0, y: 12.2, width: 10, height: 1.6),
                               cornerWidth: 0.8, cornerHeight: 0.8, transform: nil))
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dynamic Island Mac"
        return image
    }
}
