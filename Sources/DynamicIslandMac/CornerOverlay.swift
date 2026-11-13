import AppKit
import Combine

/// Arrondit les coins du bas de chaque écran avec deux petites fenêtres noires, transparentes aux clics.
final class CornerOverlayController {
    private var windows: [NSWindow] = []
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let settings = AppSettings.shared
        settings.$roundedCorners.combineLatest(settings.$cornerRadius)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, radius in self?.rebuild(enabled: enabled, radius: radius) }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild(enabled: settings.roundedCorners, radius: settings.cornerRadius)
        }
    }

    private func rebuild(enabled: Bool, radius: Double) {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard enabled else { return }
        let r = CGFloat(radius)

        for screen in NSScreen.screens {
            let f = screen.frame
            for left in [true, false] {
                let rect = NSRect(x: left ? f.minX : f.maxX - r, y: f.minY, width: r, height: r)
                let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
                w.isOpaque = false
                w.backgroundColor = .clear
                w.hasShadow = false
                w.ignoresMouseEvents = true
                w.isReleasedWhenClosed = false
                w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                w.contentView = CornerView(left: left)
                w.orderFrontRegardless()
                windows.append(w)
            }
        }
    }
}

/// Carré noir privé d'un quart de cercle : le coin de l'écran paraît arrondi.
private final class CornerView: NSView {
    private let left: Bool
    init(left: Bool) {
        self.left = left
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let path = NSBezierPath()
        if left {
            path.move(to: NSPoint(x: 0, y: 0))
            path.line(to: NSPoint(x: 0, y: b.height))
            path.appendArc(withCenter: NSPoint(x: b.width, y: b.height), radius: b.width,
                           startAngle: 180, endAngle: 270)
        } else {
            path.move(to: NSPoint(x: b.width, y: 0))
            path.line(to: NSPoint(x: 0, y: 0))
            path.appendArc(withCenter: NSPoint(x: 0, y: b.height), radius: b.width,
                           startAngle: 270, endAngle: 360)
        }
        path.close()
        NSColor.black.setFill()
        path.fill()
    }
}
