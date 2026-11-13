import AppKit
import Combine
import SwiftUI

// MARK: - SkyLight (API privée)

/// Place des fenêtres dans un « space » SkyLight de niveau absolu élevé, affiché au-dessus
/// de l'écran verrouillé. Technique utilisée par plusieurs apps d'encoche.
///
/// Affichage seulement : la session reste verrouillée et le mot de passe ou Touch ID restent
/// gérés par macOS. Les symboles sont chargés dynamiquement ; s'ils manquent, rien n'est affiché.
final class SkyLightSpace {
    static let shared = SkyLightSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private var connection: Int32 = 0
    private var space: Int32 = 0
    private var addWindows: AddWindows?
    let available: Bool

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let mainID = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let setLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            available = false
            return
        }
        // Niveau des notifications sur l'écran verrouillé : c'est lui qui passe au-dessus du verrou.
        // La constante est exportée par SkyLight ; 400 en repli si elle a disparu.
        var level: Int32 = 400
        if let constant = dlsym(handle, "kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock") {
            level = constant.assumingMemoryBound(to: Int32.self).pointee
        }
        connection = unsafeBitCast(mainID, to: MainConnectionID.self)()
        space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        let levelResult = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(connection, space, level)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(add, to: AddWindows.self)
        available = true
        debugLog("lock: espace SkyLight \(space) au niveau \(level) (réglage → \(levelResult))")
    }

    func adopt(_ window: NSWindow) {
        guard available, let addWindows else { return }
        let result = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        debugLog("lock: SkyLight space \(space), connexion \(connection), ajout fenêtre → \(result)")
    }
}

// MARK: - Contrôleur

/// Affiche les widgets et le lecteur pendant que l'écran est verrouillé.
///
/// Le signal « écran verrouillé » arrive avant que macOS dessine son écran de verrouillage.
/// Une fenêtre ouverte à ce moment-là est vite recouverte. On prépare donc tout au lancement :
/// l'espace SkyLight est créé, la fenêtre y est placée une fois pour toutes et n'en sort plus.
/// Hors verrouillage, elle reste invisible et laisse passer les clics.
final class LockScreenController {
    private let model: NotchModel
    /// Deux fenêtres : le fond plein écran (transparent aux clics) et le contenu interactif.
    private var lockBackground: NSPanel?
    private var lockWindow: NSPanel?
    private var previewBackground: NSPanel?
    private var previewWindow: NSPanel?
    private(set) var isLocked = false
    private var cancellables: Set<AnyCancellable> = []
    /// Relit l'état des lecteurs : la carte s'affiche aussi pour un morceau en pause.
    var refreshNowPlaying: (() -> Void)?

    init(model: NotchModel) {
        self.model = model
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked()
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.unlocked()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.positionAll()
        }
        prepareLockWindows()
        // Le morceau peut arriver ou changer pendant le verrouillage : le fond suit.
        model.$track.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, self.isLocked, AppSettings.shared.lockScreen else { return }
            DispatchQueue.main.async { self.lockBackground?.alphaValue = self.showsBackground ? 1 : 0 }
        }.store(in: &cancellables)
    }

    private func prepareLockWindows() {
        guard SkyLightSpace.shared.available else {
            debugLog("lock: SkyLight indisponible, pas de lecteur sur l'écran verrouillé")
            return
        }
        // Le fond d'abord, le contenu ensuite : le contenu est ajouté par-dessus dans l'espace.
        let bg = makeBackgroundWindow(level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1))
        let w = makeContentWindow(level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2))
        for window in [bg, w] {
            window.alphaValue = 0
            window.orderFrontRegardless()   // il faut un numéro de fenêtre avant de la confier à SkyLight
            SkyLightSpace.shared.adopt(window)
        }
        w.ignoresMouseEvents = true
        lockBackground = bg
        lockWindow = w
        positionAll()
        debugLog("lock: fenêtres \(bg.windowNumber) (fond) et \(w.windowNumber) (contenu) prêtes")
    }

    private var showsBackground: Bool {
        AppSettings.shared.lockScreenStyle == .fullScreen && model.track != nil
    }

    private func locked() {
        isLocked = true
        debugLog("lock: écran verrouillé (option \(AppSettings.shared.lockScreen))")
        guard AppSettings.shared.lockScreen, let w = lockWindow, let bg = lockBackground else { return }
        refreshNowPlaying?()
        positionAll()
        bg.alphaValue = showsBackground ? 1 : 0
        w.alphaValue = 1
        w.ignoresMouseEvents = false
        debugLog("lock: affiché, fond \(showsBackground), morceau \(model.track?.title ?? "aucun") (\(model.isPlaying ? "lecture" : "pause"))")
    }

    private func unlocked() {
        isLocked = false
        debugLog("lock: écran déverrouillé")
        lockBackground?.alphaValue = 0
        lockWindow?.alphaValue = 0
        lockWindow?.ignoresMouseEvents = true
    }

    /// Aperçu sur le bureau, sans verrouiller (menu de la barre des menus). Un clic n'importe où le ferme.
    func togglePreview() {
        if let w = previewWindow, w.isVisible {
            w.orderOut(nil)
            previewBackground?.orderOut(nil)
            return
        }
        let bg = previewBackground ?? makeBackgroundWindow(level: .floating)
        let w = previewWindow ?? makeContentWindow(level: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1))
        previewBackground = bg
        previewWindow = w
        positionAll()
        if showsBackground { bg.orderFrontRegardless() }
        w.orderFrontRegardless()
    }

    private func makePanel(level: NSWindow.Level) -> NSPanel {
        let w = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.canHide = false
        w.hidesOnDeactivate = false
        w.level = level
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return w
    }

    /// Le fond ne capte jamais la souris : un clic sur l'avatar ou le champ mot de passe passe au travers.
    private func makeBackgroundWindow(level: NSWindow.Level) -> NSPanel {
        let w = makePanel(level: level)
        w.ignoresMouseEvents = true
        w.contentView = NSHostingView(rootView: LockArtworkBackground(model: model))
        return w
    }

    private func makeContentWindow(level: NSWindow.Level) -> NSPanel {
        let w = makePanel(level: level)
        w.contentView = FirstMouseHostingView(rootView: LockScreenView(model: model))
        return w
    }

    private func positionAll() {
        guard let s = NSScreen.screens.first else { return } // écran principal, celui du mot de passe
        let f = s.frame
        // Le contenu s'arrête au-dessus de la zone de l'avatar et du mot de passe (17 % du bas).
        let free = f.height * 0.17
        let content = NSRect(x: f.minX, y: f.minY + free, width: f.width, height: f.height - free)
        for bg in [lockBackground, previewBackground].compactMap({ $0 }) { bg.setFrame(f, display: true) }
        for w in [lockWindow, previewWindow].compactMap({ $0 }) { w.setFrame(content, display: true) }
    }
}

// MARK: - Vues

struct LockScreenView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        GeometryReader { geo in
            let fullScreen = settings.lockScreenStyle == .fullScreen && model.track != nil
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if fullScreen {
                        // Le fond recouvre l'horloge de macOS : on dessine la nôtre.
                        LockClock(accent: model.accent)
                            .padding(.top, geo.size.height * 0.07)
                        if settings.lockScreenWidgets { LockWidgetsRow(model: model).padding(.top, 8) }
                    } else {
                        Spacer().frame(height: geo.size.height * 0.24) // sous l'horloge de macOS
                        if settings.lockScreenWidgets { LockWidgetsRow(model: model) }
                    }
                    Spacer(minLength: 16)
                    if let track = model.track {
                        VStack(spacing: 22) {
                            if settings.lockScreenStyle != .card {
                                ArtworkView(image: model.artwork,
                                            size: min(geo.size.height * (fullScreen ? 0.34 : 0.28), 320),
                                            radius: 14)
                                    .shadow(color: .black.opacity(0.5), radius: 34, y: 18)
                                    .id(track.id)
                                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                            }
                            LockPlayerCard(model: model, track: track, compact: fullScreen)
                        }
                        .offset(y: -CGFloat(settings.lockScreenOffset))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Spacer(minLength: 28)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.track?.id)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: settings.lockScreenStyle)
        .environment(\.colorScheme, .dark)
    }
}

/// Fond plein écran : la pochette en grand, nette au centre et floutée vers les bords,
/// avec un voile en haut et en bas pour que l'heure et le lecteur restent lisibles.
struct LockArtworkBackground: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                if let image = model.artwork {
                    // Couche floue : remplit tout l'écran.
                    art(image, size).blur(radius: 70, opaque: true).saturation(1.15)
                    // Couche nette : visible au centre, fondue vers les bords.
                    art(image, size)
                        .mask(RadialGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: 0.45),
                                                     .init(color: .clear, location: 1)],
                                             center: .center, startRadius: 0,
                                             endRadius: max(size.width, size.height) * 0.62))
                } else {
                    LinearGradient(colors: [model.accent.opacity(0.7), .black], startPoint: .top, endPoint: .bottom)
                }
                // Lisibilité de l'heure (haut) et du lecteur (bas), et vignette sur les bords.
                LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0),
                                       .init(color: .clear, location: 0.32),
                                       .init(color: .clear, location: 0.6),
                                       .init(color: .black.opacity(0.55), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center,
                               startRadius: min(size.width, size.height) * 0.45,
                               endRadius: max(size.width, size.height) * 0.75)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            // Option : laisser voir l'avatar et le champ mot de passe en bas.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                         .init(color: .black, location: settings.lockScreenShowPassword ? 0.8 : 1),
                                         .init(color: settings.lockScreenShowPassword ? .clear : .black, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .animation(.easeInOut(duration: 0.6), value: model.artwork.map { ObjectIdentifier($0) })
        .environment(\.colorScheme, .dark)
    }

    private func art(_ image: NSImage, _ size: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

/// Date et heure en grand, à empattements, teintées par la pochette.
struct LockClock: View {
    let accent: Color

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(spacing: 0) {
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 112, weight: .bold, design: .serif).monospacedDigit())
                    .foregroundStyle(LinearGradient(colors: [.white, accent.opacity(0.9)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
    }
}

/// Rangée « météo · batterie · écouteurs », comme sous l'horloge d'un écran verrouillé.
struct LockWidgetsRow: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 22) {
            if let w = model.weather {
                widget(w.symbol, "\(w.temperature)°")
            }
            if let b = model.battery {
                widget(b.pluggedIn ? "bolt.fill" : batterySymbol(b), "\(b.percent) %")
            }
            if let next = model.events.first(where: { !$0.allDay && $0.start > Date() }) {
                widget("calendar", next.start.formatted(.dateTime.hour().minute()))
            }
        }
        .font(.system(size: 17, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white.opacity(0.9))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }

    private func widget(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
    }
}

struct LockPlayerCard: View {
    @ObservedObject var model: NotchModel
    let track: Track
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 14) {
                if !compact { ArtworkView(image: model.artwork, size: 58, radius: 12) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 14, weight: .semibold))
                    Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                .lineLimit(1)
                .foregroundStyle(.white)
                Spacer(minLength: 8)
                EqualizerBars(color: .white.opacity(0.8), playing: model.isPlaying, barCount: 5, height: 16)
            }
            LyricLineView(model: model).frame(height: 18)
            ProgressBarView(model: model, duration: track.duration)
            ControlsView(model: model, spacing: compact ? 26 : 34)
        }
        .padding(compact ? 14 : 18)
        .frame(width: compact ? 340 : 380)
        .modifier(GlassCard(cornerRadius: 30))
    }
}

/// Verre « Liquid Glass » sur macOS 26, matériau flou sinon.
struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
    }
}
