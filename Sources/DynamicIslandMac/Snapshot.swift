import AppKit
import SwiftUI

/// `DynamicIslandMac --snapshot <dossier>` : rend chaque état de l'île en PNG avec des données fictives,
/// sans fenêtre ni permission d'enregistrement d'écran. Sert à vérifier le design.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let cases: [(String, (NotchModel) -> Void)] = [
            ("1-expanded-player", { m in
                m.isExpanded = true
                fillTrack(m)
            }),
            ("2-live", { m in fillTrack(m) }),
            ("3-charging", { m in
                m.activity = .power(BatteryState(percent: 76, charging: true, pluggedIn: true))
            }),
            ("4-airpods", { m in
                m.activity = .headphones(name: "AirPods Pro", symbol: "airpodspro", battery: 88, connected: true)
            }),
            ("5-expanded-idle", { m in m.isExpanded = true; fillWeather(m) }),
            ("6-tab-lyrics", { m in m.isExpanded = true; m.tab = .lyrics; fillTrack(m) }),
            ("7-tab-shelf", { m in
                m.isExpanded = true; m.tab = .shelf
                m.shelf = ["/System/Applications/Notes.app", "/System/Library/CoreServices/Finder.app",
                           "/System/Applications/Preview.app"].map { URL(fileURLWithPath: $0) }
            }),
            ("8-tab-agenda", { m in m.isExpanded = true; m.tab = .agenda; fillEvents(m); fillWeather(m) }),
            ("9-tab-timer", { m in
                m.isExpanded = true; m.tab = .timer
                m.timerEnd = Date().addingTimeInterval(299); m.stopwatchAccumulated = 83.4
            }),
            ("10-volume", { m in m.activity = .volume(level: 0.62, muted: false) }),
            ("11-live-timer", { m in m.timerEnd = Date().addingTimeInterval(1499) }),
            ("12-live-paused", { m in fillTrack(m); m.isPlaying = false }),
        ]

        for (name, configure) in cases {
            let model = NotchModel()
            model.notchSize = CGSize(width: 185, height: 32)
            model.hasPhysicalNotch = true
            model.battery = BatteryState(percent: 76, charging: false, pluggedIn: false)
            configure(model)

            let view = NotchRootView(model: model)
                .frame(width: 760, height: 230)
                .background(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.65)],
                                           startPoint: .top, endPoint: .bottom))
            if let rep = render(view, size: CGSize(width: 760, height: 230)) {
                let url = dir.appendingPathComponent("\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("snapshot: \(url.path)")
            }
        }

        // Écran verrouillé, sur un fond qui imite un fond d'écran.
        for big in [false, true] {
            let model = NotchModel()
            model.battery = BatteryState(percent: 60, charging: true, pluggedIn: true)
            fillTrack(model)
            fillWeather(model)
            fillEvents(model)
            AppSettings.shared.lockScreenBigArt = big
            let view = LockScreenView(model: model)
                .frame(width: 480, height: 560)
                .background(LinearGradient(colors: [Color(red: 0.1, green: 0.25, blue: 0.4),
                                                    Color(red: 0.55, green: 0.7, blue: 0.85)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
            if let rep = render(view, size: CGSize(width: 480, height: 560)) {
                let url = dir.appendingPathComponent("lock-\(big ? "big" : "card").png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("snapshot: \(url.path)")
            }
        }
        AppSettings.shared.lockScreenBigArt = false

        // Logo de la barre des menus, agrandi, sur fond clair et sur fond sombre.
        let icon = MenuBarIcon.make()
        let iconView = HStack(spacing: 30) {
            ForEach([Color(white: 0.92), Color(white: 0.12)], id: \.self) { bg in
                HStack(spacing: 24) {
                    Image(nsImage: icon).resizable().renderingMode(.template).interpolation(.high)
                        .frame(width: 160, height: 128)
                    Image(nsImage: icon).renderingMode(.template)
                }
                .foregroundStyle(bg == Color(white: 0.92) ? .black : .white)
                .padding(20)
                .background(bg)
            }
        }
        if let rep = render(iconView, size: CGSize(width: 560, height: 180)) {
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("menubar-icon.png"))
        }

        // Hors bundle, l'app n'a pas d'icône : on prend celle du README.
        if let icon = NSImage(contentsOfFile: "docs/icon.png") { NSApplication.shared.applicationIconImage = icon }
        if let rep = render(SettingsView(settings: .shared), size: CGSize(width: 480, height: 660)) {
            let url = dir.appendingPathComponent("settings.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("snapshot: \(url.path)")
        }
        return true
    }

    /// Rend la vue dans une vraie NSHostingView hors écran : contrairement à ImageRenderer,
    /// les vues AppKit (ScrollView, flou, zones de dépôt) sont dessinées.
    private static func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep? {
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6)) // laisse SwiftUI finir la mise en page
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    private static func fillWeather(_ m: NotchModel) {
        m.weather = WeatherInfo(temperature: 14, high: 17, low: 9, symbol: "cloud.sun.fill", label: "Éclaircies",
                                place: "Paris")
    }

    private static func fillEvents(_ m: NotchModel) {
        let now = Date()
        m.events = [
            AgendaEvent(id: "1", title: "Point produit", start: now.addingTimeInterval(1500),
                        end: now.addingTimeInterval(3300), allDay: false, color: .blue),
            AgendaEvent(id: "2", title: "Déjeuner avec Sam", start: now.addingTimeInterval(7200),
                        end: now.addingTimeInterval(10800), allDay: false, color: .orange),
            AgendaEvent(id: "3", title: "Revue de code", start: now.addingTimeInterval(86400),
                        end: now.addingTimeInterval(90000), allDay: false, color: .green),
        ]
    }

    private static func fillTrack(_ m: NotchModel) {
        m.track = Track(id: "demo", title: "Midnight Avenue", artist: "The Paper Lanterns",
                        album: "Neon Weather", duration: 214, source: .spotify)
        m.isPlaying = true
        m.setPosition(83)
        m.lyrics = [
            LyricLine(time: 70, text: "We drove until the city lights went out"),
            LyricLine(time: 80, text: "Counting every streetlamp like a heartbeat"),
            LyricLine(time: 90, text: "Midnight on the avenue"),
        ]
        m.artwork = demoArtwork()
        m.accent = m.artwork?.accentColor() ?? .white
    }

    private static func demoArtwork() -> NSImage {
        let size = NSSize(width: 300, height: 300)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1)])?
                .draw(in: rect, angle: -60)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 95, y: 95, width: 110, height: 110)).fill()
            return true
        }
    }
}
