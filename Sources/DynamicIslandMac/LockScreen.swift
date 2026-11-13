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
        connection = unsafeBitCast(mainID, to: MainConnectionID.self)()
        space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        _ = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(connection, space, 100)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [space] as CFArray)
        addWindows = unsafeBitCast(add, to: AddWindows.self)
        available = true
    }

    func adopt(_ window: NSWindow) {
        guard available, let addWindows else { return }
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}

// MARK: - Contrôleur

/// Affiche les widgets et le lecteur pendant que l'écran est verrouillé.
final class LockScreenController {
    private let model: NotchModel
    private var lockWindow: NSPanel?
    private var previewWindow: NSPanel?
    private(set) var isLocked = false

    init(model: NotchModel) {
        self.model = model
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked()
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.unlocked()
        }
    }

    private func locked() {
        isLocked = true
        guard AppSettings.shared.lockScreen, SkyLightSpace.shared.available else { return }
        if lockWindow == nil {
            let w = makeWindow()
            w.orderFrontRegardless() // il faut un numéro de fenêtre avant de la confier à SkyLight
            SkyLightSpace.shared.adopt(w)
            lockWindow = w
        }
        guard let w = lockWindow else { return }
        position(w)
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            w.animator().alphaValue = 1
        }
    }

    private func unlocked() {
        isLocked = false
        guard let w = lockWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            w.animator().alphaValue = 0
        }, completionHandler: {
            if !self.isLocked { w.orderOut(nil) }
        })
    }

    /// Aperçu sur le bureau, sans verrouiller (menu de la barre des menus).
    func togglePreview() {
        if let w = previewWindow, w.isVisible {
            w.orderOut(nil)
            return
        }
        let w = previewWindow ?? makeWindow()
        w.level = .floating
        position(w)
        w.orderFrontRegardless()
        previewWindow = w
    }

    private func makeWindow() -> NSPanel {
        let w = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.contentView = FirstMouseHostingView(rootView: LockScreenView(model: model))
        return w
    }

    /// Zone centrale de l'écran seulement : l'horloge système en haut et le champ
    /// de mot de passe en bas restent visibles et accessibles.
    private func position(_ w: NSWindow) {
        guard let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let f = s.frame
        let size = CGSize(width: 480, height: f.height * 0.56)
        w.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.2,
                          width: size.width, height: size.height), display: true)
    }
}

// MARK: - Vues

struct LockScreenView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            LockWidgetsRow(model: model)
            Spacer(minLength: 12)
            if let track = model.track {
                VStack(spacing: 18) {
                    if settings.lockScreenBigArt {
                        ArtworkView(image: model.artwork, size: 220, radius: 26)
                            .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
                            .id(track.id)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    LockPlayerCard(model: model, track: track)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.track?.id)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: settings.lockScreenBigArt)
        .environment(\.colorScheme, .dark)
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

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ArtworkView(image: model.artwork, size: 58, radius: 12)
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
            ControlsView(model: model, spacing: 34)
        }
        .padding(18)
        .frame(width: 380)
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
