import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Forme

/// Silhouette d'encoche : coins hauts évasés vers l'extérieur, coins bas arrondis.
struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set { flare = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, (rect.height - flare) / 2, (rect.width - 2 * flare) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + flare, y: rect.minY + flare),
                       control: CGPoint(x: rect.minX + flare, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + flare, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + flare + r, y: rect.maxY),
                       control: CGPoint(x: rect.minX + flare, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - flare - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - flare, y: rect.maxY - r),
                       control: CGPoint(x: rect.maxX - flare, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - flare, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Flou d'arrière-plan AppKit, pour le thème « Verre ».
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var dark = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
    }
}

// MARK: - Racine

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared
    @State private var dropTargeted = false

    var body: some View {
        let size = model.currentSize
        let expanded = model.mode == .expanded

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                background(expanded: expanded)
                content
                    .padding(.horizontal, NotchModel.flare)
                    .transition(.blurReplace)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(flare: NotchModel.flare, bottomRadius: expanded ? 30 : 11))
            .overlay {
                if dropTargeted {
                    NotchShape(flare: NotchModel.flare, bottomRadius: 30)
                        .stroke(model.accent.opacity(0.9), lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(expanded ? 0.55 : 0), radius: 18, y: 8)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadFileURLs(providers) { urls in
                    model.addToShelf(urls)
                    model.tab = .shelf
                }
                return true
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.mode)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: model.tab)
        // L'île réduite reste noire pour se fondre dans l'encoche ; le thème s'applique à l'île ouverte.
        .environment(\.colorScheme, expanded && settings.theme == .light ? .light : .dark)
    }

    @ViewBuilder private func background(expanded: Bool) -> some View {
        switch (expanded, settings.theme) {
        case (true, .glass):
            ZStack {
                VisualEffectView(material: .hudWindow, dark: true)
                // Assez dense pour que ce qui passe derrière (neige de Flocon, fenêtres) ne se voie presque plus.
                Color.black.opacity(0.5)
            }
        case (true, .light):
            ZStack {
                VisualEffectView(material: .popover, dark: false)
                Color.white.opacity(0.78)
            }
        default:
            Color.black
        }
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .idle:
            Color.clear
        case .live:
            LiveView(model: model)
        case .activity:
            if let activity = model.activity { ActivityView(activity: activity, notchWidth: model.notchSize.width) }
        case .expanded:
            ExpandedView(model: model)
        }
    }
}

func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for p in providers where p.canLoadObject(ofClass: URL.self) {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

// MARK: - Île réduite : lecture, minuteur ou chrono

struct LiveView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: model.notchSize.width)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: model.notchSize.height)
    }

    @ViewBuilder private var leading: some View {
        if model.timerRunning {
            Image(systemName: "timer").foregroundStyle(.orange).font(.system(size: 14, weight: .semibold))
        } else if model.stopwatchRunning {
            Image(systemName: "stopwatch").foregroundStyle(.cyan).font(.system(size: 14, weight: .semibold))
        } else {
            ArtworkView(image: model.artwork, size: model.notchSize.height - 10, radius: 6)
        }
    }

    @ViewBuilder private var trailing: some View {
        if model.timerRunning || model.stopwatchRunning {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                Text(formatDuration(model.timerRunning
                                    ? model.timerRemaining(at: ctx.date).rounded(.up)
                                    : model.stopwatchElapsed(at: ctx.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(model.timerRunning ? .orange : .cyan)
            }
        } else {
            EqualizerBars(color: model.accent, playing: model.isPlaying, barCount: 4, height: 13)
        }
    }
}

// MARK: - Île réduite : notification système

struct ActivityView: View {
    let activity: Activity
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: activity.id)
                Text(leadingText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: notchWidth + 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var trailing: some View {
        if case .volume(let level, let muted) = activity {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.2))
                    Capsule().fill(Color.primary).frame(width: geo.size.width * CGFloat(muted ? 0 : level))
                }
            }
            .frame(width: 74, height: 5)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: level)
        } else {
            Text(trailingText)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private var leadingSymbol: String {
        switch activity {
        case .power(let b): return b.pluggedIn ? "bolt.fill" : "battery.25"
        case .headphones(_, let symbol, _, _): return symbol
        case .volume(let level, let muted):
            if muted || level == 0 { return "speaker.slash.fill" }
            return level < 0.33 ? "speaker.wave.1.fill" : (level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        case .message(let symbol, _, _, _): return symbol
        }
    }

    private var leadingText: String {
        switch activity {
        case .power(let b): return b.pluggedIn ? "En charge" : "Batterie faible"
        case .headphones(let name, _, _, let connected): return connected ? name : "Déconnecté"
        case .volume: return "Volume"
        case .message(_, let text, _, _): return text
        }
    }

    private var trailingText: String {
        switch activity {
        case .power(let b): return "\(b.percent) %"
        case .headphones(_, _, let battery, let connected):
            if !connected { return "" }
            return battery.map { "\($0) %" } ?? "Connecté"
        case .volume: return ""
        case .message(_, _, let detail, _): return detail
        }
    }

    private var tint: Color {
        switch activity {
        case .power(let b): return b.pluggedIn ? .green : (b.percent <= 10 ? .red : .orange)
        case .headphones(_, _, _, let connected): return connected ? Color.primary : .gray
        case .volume: return Color.primary
        case .message(_, _, _, let tint): return tint
        }
    }
}

// MARK: - Île ouverte

struct ExpandedView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch model.tab {
                case .player:
                    if let track = model.track {
                        PlayerView(model: model, track: track)
                    } else {
                        IdleClockView(model: model)
                    }
                case .clipboard: ClipboardView(model: model)
                case .shelf: ShelfView(model: model)
                case .agenda: AgendaView(model: model)
                case .timer: TimerTabView(model: model)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .id(model.tab)
        }
    }

    /// Bande du haut, de part et d'autre de l'encoche physique : onglets à gauche, état à droite.
    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(IslandTab.allCases) { tab in
                    TabButton(tab: tab, selected: model.tab == tab, accent: model.accent) {
                        model.tab = tab
                        Haptics.tap(.alignment)
                    }
                }
            }
            Spacer(minLength: model.notchSize.width + 12)
            HStack(spacing: 10) {
                if let w = model.weather {
                    HStack(spacing: 4) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                        Text("\(w.temperature)°").monospacedDigit()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.75))
                }
                if let b = model.battery { BatteryBadge(battery: b) }
                SettingsGearButton { model.openSettings?() }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: model.notchSize.height)
    }
}

struct TabButton: View {
    let tab: IslandTab
    let selected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(hovering ? 0.8 : 0.45))
                .frame(width: 28, height: 22)
                .background(Capsule().fill(Color.primary.opacity(selected ? 0.16 : (hovering ? 0.07 : 0))))
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { hovering = $0 }
    }
}

struct SettingsGearButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(hovering ? 0.95 : 0.55))
                .frame(width: 24, height: 22)
                .background(Capsule().fill(Color.primary.opacity(hovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .help("Réglages")
        .onHover { hovering = $0 }
    }
}

// MARK: Lecture

struct PlayerView: View {
    @ObservedObject var model: NotchModel
    let track: Track

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ArtworkView(image: model.artwork, size: 104, radius: 18)
                .shadow(color: model.accent.opacity(0.45), radius: 16, y: 4)
                .id(track.id)
                .transition(.scale(scale: 0.85).combined(with: .opacity))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text(track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                    .lineLimit(1)
                    .id(track.id)
                    .transition(.push(from: .bottom))
                    Spacer(minLength: 8)
                    EqualizerBars(color: model.accent, playing: model.isPlaying, barCount: 5, height: 18)
                        .padding(.top, 2)
                }
                .clipped()

                LyricLineView(model: model)
                    .frame(height: 20)
                    .padding(.top, 6)

                ProgressBarView(model: model, duration: track.duration)
                    .padding(.top, 6)

                ControlsView(model: model)
                    .padding(.top, 4)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: track.id)
    }
}

struct ControlsView: View {
    @ObservedObject var model: NotchModel
    var spacing: CGFloat = 26

    var body: some View {
        HStack(spacing: spacing) {
            ToggleIconButton(symbol: "shuffle", active: model.shuffle) { model.controls?.toggleShuffle() }
            ControlButton(symbol: "backward.fill", size: 15) { model.controls?.previousTrack(); Haptics.tap() }
            ControlButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 21) {
                model.controls?.togglePlayPause()
                Haptics.tap()
            }
            ControlButton(symbol: "forward.fill", size: 15) { model.controls?.nextTrack(); Haptics.tap() }
            ToggleIconButton(symbol: model.repeatMode == .one ? "repeat.1" : "repeat",
                             active: model.repeatMode != .off) { model.controls?.cycleRepeat() }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { AudioOutputMenu() }
    }
}

/// Petit bouton à deux états (aléatoire, répétition).
struct ToggleIconButton: View {
    let symbol: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: { action(); Haptics.tap() }) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(active ? Color.primary : Color.primary.opacity(hovering ? 0.7 : 0.4))
                .frame(width: 26, height: 24)
                .background(Circle().fill(Color.primary.opacity(active ? 0.16 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Choix de la sortie audio (haut-parleurs, AirPods, écran, AirPlay…).
struct AudioOutputMenu: View {
    @State private var outputs: [AudioOutput] = []
    @State private var current: AudioObjectID = 0

    var body: some View {
        Menu {
            ForEach(outputs) { output in
                Button {
                    AudioOutputs.setDefault(output.id)
                    current = output.id
                    Haptics.tap()
                } label: {
                    Label(output.name, systemImage: output.id == current ? "checkmark" : output.symbol)
                }
            }
        } label: {
            Image(systemName: outputs.first(where: { $0.id == current })?.symbol ?? "airplayaudio")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sortie audio")
        .onAppear(perform: reload)
        .onHover { if $0 { reload() } }
    }

    private func reload() {
        outputs = AudioOutputs.all()
        current = AudioOutputs.defaultOutput
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Color.primary)
                .frame(width: 34, height: 30)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct ProgressBarView: View {
    @ObservedObject var model: NotchModel
    let duration: Double
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = model.position(at: context.date)
            let fraction = dragFraction ?? (duration > 0 ? position / duration : 0)
            HStack(spacing: 8) {
                Text(formatDuration(dragFraction.map { $0 * duration } ?? position))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.18))
                        Capsule().fill(model.accent)
                            .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    }
                    .frame(height: dragFraction == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in dragFraction = max(0, min(1, v.location.x / geo.size.width)) }
                            .onEnded { _ in
                                if let f = dragFraction { model.controls?.seek(to: f * duration) }
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 12)
                Text("-" + formatDuration(max(0, duration - position)))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.primary.opacity(0.5))
            .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
        }
    }
}

struct LyricLineView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: settings.progressiveLyrics ? 0.05 : 0.2)) { context in
            let index = model.currentLyricIndex(at: context.date)
            let text = index.map { model.lyrics[$0].text } ?? ""
            let shown = text.isEmpty ? (model.lyrics.isEmpty ? "" : "♪") : text
            ZStack(alignment: .leading) {
                if settings.progressiveLyrics {
                    KaraokeText(text: shown, progress: model.lyricProgress(at: context.date), accent: model.accent)
                        .id(index ?? -1)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                } else {
                    Text(shown)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.accent)
                        .shadow(color: model.accent.opacity(0.6), radius: 6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .id(index ?? -1)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)
        }
    }
}

/// La ligne s'allume de gauche à droite au rythme du chant. Le minutage par mot n'existe pas
/// dans les paroles LRC : l'avancement est réparti sur la durée de la ligne.
struct KaraokeText: View {
    let text: String
    let progress: Double
    let accent: Color

    var body: some View {
        let label = Text(text)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        label
            .foregroundStyle(Color.primary.opacity(0.35))
            .overlay(alignment: .leading) {
                label
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.6), radius: 6)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            LinearGradient(stops: [.init(color: .black, location: 0),
                                                   .init(color: .black, location: max(0, progress - 0.02)),
                                                   .init(color: .clear, location: min(1, progress + 0.04))],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: geo.size.width)
                        }
                    }
            }
    }
}

// MARK: Presse-papiers

struct ClipboardView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        if !settings.clipboardHistory {
            EmptyStateView(symbol: "doc.on.clipboard", text: "Historique désactivé dans les réglages.")
        } else if model.clipboard.isEmpty {
            EmptyStateView(symbol: "doc.on.clipboard", text: "Copie quelque chose : ça apparaîtra ici.")
        } else {
            VStack(spacing: 6) {
                HStack {
                    Text("Clique pour recopier").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.5))
                    Spacer()
                    SmallPill(symbol: "trash", text: "Effacer") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.clipboard.removeAll() }
                    }
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(model.clipboard) { item in
                            ClipRow(item: item) { model.copyClip?(item) }
                        }
                    }
                }
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let copy: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            copy()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "Image")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text([item.app, item.date.formatted(.relative(presentation: .named))]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
                Spacer(minLength: 6)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied ? Color.green : Color.primary.opacity(hovering ? 0.8 : 0))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = item.image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: item.isLink ? "link" : "text.alignleft")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
        }
    }
}

// MARK: Étagère

struct ShelfView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        if model.shelf.isEmpty {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 26))
                        Text("Dépose des fichiers ici").font(.system(size: 13, weight: .medium))
                        Text("Ils restent là jusqu'à ce que tu les glisses ailleurs.")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    .foregroundStyle(Color.primary.opacity(0.7))
                }
                .padding(.bottom, 16)
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text("\(model.shelf.count) élément\(model.shelf.count > 1 ? "s" : "")")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.primary.opacity(0.5))
                    Spacer()
                    SmallPill(symbol: "airplayaudio", text: "AirDrop") { Shelf.airDrop(model.shelf) }
                    SmallPill(symbol: "trash", text: "Vider") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.shelf.removeAll() }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.shelf, id: \.self) { url in
                            ShelfItemView(url: url) { model.removeFromShelf(url) }
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }
}

enum Shelf {
    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }
}

struct ShelfItemView: View {
    let url: URL
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76, height: 26, alignment: .top)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(Color.primary, .gray.opacity(0.8))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Ouvrir") { NSWorkspace.shared.open(url) }
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Envoyer par AirDrop") { Shelf.airDrop([url]) }
            Divider()
            Button("Retirer de l'étagère", action: remove)
        }
        .help(url.path)
    }
}

struct SmallPill: View {
    let symbol: String
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if symbol.isEmpty { Text(text) } else { Label(text, systemImage: symbol) }
            }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(hovering ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: Agenda

struct AgendaView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        if !settings.showCalendar {
            EmptyStateView(symbol: "calendar", text: "Agenda désactivé dans les réglages.")
        } else if model.events.isEmpty {
            EmptyStateView(symbol: "calendar.badge.checkmark", text: "Rien de prévu aujourd'hui ni demain.")
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(model.events.prefix(4)) { event in
                    HStack(spacing: 10) {
                        Capsule().fill(event.color).frame(width: 4, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
                            Text(timeRange(event)).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
                        }
                        .lineLimit(1)
                        Spacer()
                        Text(relative(event))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(event.start <= Date() ? event.color : Color.primary.opacity(0.55))
                    }
                }
            }
        }
    }

    private func timeRange(_ e: AgendaEvent) -> String {
        if e.allDay { return "Toute la journée" }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(e.start.formatted(f)) – \(e.end.formatted(f))"
    }

    private func relative(_ e: AgendaEvent) -> String {
        let now = Date()
        if e.start <= now { return "En cours" }
        if !Calendar.current.isDateInToday(e.start) { return "Demain" }
        let minutes = Int(e.start.timeIntervalSince(now) / 60)
        return minutes < 60 ? "dans \(minutes) min" : "dans \(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }
}

// MARK: Minuteur et chrono

struct TimerTabView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 10) {
                Label("Minuteur", systemImage: "timer").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    Text(formatDuration(model.timerRunning ? model.timerRemaining(at: ctx.date).rounded(.up) : 0))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(model.timerRunning ? Color.primary : Color.primary.opacity(0.35))
                }
                if model.timerRunning {
                    HStack(spacing: 8) {
                        SmallPill(symbol: "plus", text: "1 min") { model.addTimerMinute() }
                        SmallPill(symbol: "xmark", text: "Arrêter") { model.cancelTimer() }
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach([1.0, 5, 10, 25], id: \.self) { m in
                            SmallPill(symbol: "", text: "\(Int(m)) min") { model.startTimer(minutes: m) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 110)

            VStack(spacing: 10) {
                Label("Chrono", systemImage: "stopwatch").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.cyan)
                TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                    let t = model.stopwatchElapsed(at: ctx.date)
                    Text(formatDuration(t) + String(format: ",%d", Int((t * 10).truncatingRemainder(dividingBy: 10))))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(model.stopwatchRunning || t > 0 ? Color.primary : Color.primary.opacity(0.35))
                }
                HStack(spacing: 8) {
                    SmallPill(symbol: model.stopwatchRunning ? "pause.fill" : "play.fill",
                              text: model.stopwatchRunning ? "Pause" : "Démarrer") { model.toggleStopwatch() }
                    SmallPill(symbol: "arrow.counterclockwise", text: "Zéro") { model.resetStopwatch() }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }
}

// MARK: Repos

struct IdleClockView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.primary)
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.55))
                HStack(spacing: 14) {
                    if let w = model.weather {
                        Label("\(w.label), \(w.temperature)° (\(w.low)° / \(w.high)°)", systemImage: w.symbol)
                    }
                    if let next = model.events.first(where: { !$0.allDay }) {
                        Label("\(next.title) à \(next.start.formatted(.dateTime.hour().minute()))", systemImage: "calendar")
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.primary.opacity(0.45))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 14)
    }
}

// MARK: - Petits composants

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .id(image.map { ObjectIdentifier($0) })
        .transition(.opacity)
    }
}

struct EqualizerBars: View {
    let color: Color
    let playing: Bool
    let barCount: Int
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Double(i) * 1.7
                    let level = playing
                        ? 0.35 + 0.65 * abs(sin(t * (3.1 + Double(i) * 0.9) + phase) * cos(t * 1.3 + phase))
                        : 0.18
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: max(3, height * level))
                }
            }
            .frame(height: height)
        }
    }
}

struct BatteryBadge: View {
    let battery: BatteryState

    var body: some View {
        HStack(spacing: 5) {
            Text("\(battery.percent) %")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.primary.opacity(0.7))
            Image(systemName: batterySymbol(battery))
                .font(.system(size: 13))
                .foregroundStyle(battery.pluggedIn ? .green : (battery.percent <= 20 ? .red : Color.primary.opacity(0.8)))
        }
    }
}

func batterySymbol(_ battery: BatteryState) -> String {
    if battery.charging { return "battery.100.bolt" }
    switch battery.percent {
    case ..<13: return "battery.0"
    case ..<38: return "battery.25"
    case ..<63: return "battery.50"
    case ..<88: return "battery.75"
    default: return "battery.100"
    }
}
