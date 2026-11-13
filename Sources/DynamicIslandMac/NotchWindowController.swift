import AppKit
import SwiftUI

/// Panneau transparent, sans bordure, posé au-dessus de la barre des menus.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Les boutons répondent au premier clic, même si Dynamic Island Mac n'est pas l'app active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchWindowController {
    private let model: NotchModel
    private let panel: NotchPanel
    private var screen: NSScreen?
    private var mouseTimer: Timer?
    private var hoverStart: Date?

    /// Taille fixe de la fenêtre : la forme animée vit dedans.
    private let windowSize = CGSize(width: 760, height: 300)

    init(model: NotchModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = !model.isExpanded
        panel.contentView = FirstMouseHostingView(rootView: NotchRootView(model: model))

        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }

        // Suivi du pointeur par sondage : aucune permission d'accessibilité requise.
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.trackMouse()
        }
    }

    private func targetScreen() -> NSScreen? {
        if AppSettings.shared.preferMainScreen { return NSScreen.main }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    func reposition() {
        guard let s = targetScreen() else { return }
        screen = s

        if s.safeAreaInsets.top > 0,
           let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            model.hasPhysicalNotch = true
            model.notchSize = CGSize(width: s.frame.width - left.width - right.width,
                                     height: s.safeAreaInsets.top)
        } else {
            // Pas d'encoche : on dessine notre propre île, de la hauteur de la barre des menus.
            model.hasPhysicalNotch = false
            let menuBar = max(s.frame.maxY - s.visibleFrame.maxY, 24)
            model.notchSize = CGSize(width: 180, height: menuBar)
        }

        let frame = NSRect(x: s.frame.midX - windowSize.width / 2,
                           y: s.frame.maxY - windowSize.height,
                           width: windowSize.width, height: windowSize.height)
        panel.setFrame(frame, display: true)
    }

    /// Rectangle de la forme visible, en coordonnées écran.
    private func shapeRect(_ size: CGSize, in s: NSScreen) -> NSRect {
        NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height,
               width: size.width, height: size.height + 2) // +2 : inclut le bord haut de l'écran
    }

    private func trackMouse() {
        guard let s = screen, !model.pinnedExpanded else { return }
        let p = NSEvent.mouseLocation

        if model.isExpanded {
            let rect = shapeRect(model.size(for: .expanded), in: s).insetBy(dx: -14, dy: -14)
            if !rect.contains(p) { setExpanded(false) }
        } else {
            let rect = shapeRect(model.currentSize, in: s).insetBy(dx: -4, dy: -3)
            if rect.contains(p) {
                // Petit délai pour ne pas ouvrir l'île en traversant la barre des menus.
                if hoverStart == nil { hoverStart = Date() }
                if let start = hoverStart, Date().timeIntervalSince(start) >= AppSettings.shared.hoverDelay {
                    // Bouton gauche enfoncé en arrivant : on traîne sans doute un fichier vers l'étagère.
                    if NSEvent.pressedMouseButtons & 1 != 0 { model.tab = .shelf }
                    setExpanded(true)
                }
            } else {
                hoverStart = nil
            }
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        hoverStart = nil
        panel.ignoresMouseEvents = !expanded
        withAnimation(.spring(response: 0.42, dampingFraction: expanded ? 0.74 : 0.86)) {
            model.isExpanded = expanded
        }
        if expanded { Haptics.tap(.alignment) }
    }
}
