import AppKit
import SwiftUI

enum PlayerSource: String {
    case spotify = "Spotify"
    case music = "Musique"

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }
}

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double // secondes
    var source: PlayerSource
}

struct LyricLine: Equatable {
    var time: Double
    var text: String
}

struct BatteryState: Equatable {
    var percent: Int
    var charging: Bool
    var pluggedIn: Bool
}

struct WeatherInfo: Equatable {
    var temperature: Int
    var high: Int
    var low: Int
    var symbol: String
    var label: String
    var place: String
}

/// Un élément copié, gardé en mémoire seulement (jamais écrit sur le disque).
struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    var text: String?
    var image: NSImage?
    var app: String?
    var date: Date

    var isLink: Bool {
        guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    static func == (a: ClipItem, b: ClipItem) -> Bool { a.id == b.id }
}

struct AgendaEvent: Equatable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: Color
}

enum Activity: Equatable {
    case power(BatteryState)
    case headphones(name: String, symbol: String, battery: Int?, connected: Bool)
    case volume(level: Float, muted: Bool)
    case message(symbol: String, text: String, detail: String, tint: Color)

    /// Identité stable : une nouvelle valeur du même type ne relance pas l'animation d'entrée.
    var id: String {
        switch self {
        case .power(let b): return "power-\(b.pluggedIn)"
        case .headphones(let name, _, _, let connected): return "hp-\(name)-\(connected)"
        case .volume: return "volume"
        case .message(_, let text, _, _): return "msg-\(text)"
        }
    }
}

enum IslandTab: String, CaseIterable, Identifiable {
    case player, clipboard, shelf, agenda, timer
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .player: return "play.circle.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        case .agenda: return "calendar"
        case .timer: return "timer"
        }
    }

    var title: String {
        switch self {
        case .player: return "Lecture"
        case .clipboard: return "Presse-papiers"
        case .shelf: return "Étagère"
        case .agenda: return "Agenda"
        case .timer: return "Minuteur"
        }
    }
}

enum RepeatMode { case off, all, one }

/// Ce que l'île sait faire faire au lecteur.
protocol PlaybackControls: AnyObject {
    func togglePlayPause()
    func toggleShuffle()
    func cycleRepeat()
    func nextTrack()
    func previousTrack()
    func seek(to seconds: Double)
}

final class NotchModel: ObservableObject {
    enum Mode: Equatable { case idle, live, activity, expanded }

    // Géométrie
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasPhysicalNotch = false

    // État d'ouverture
    @Published var isExpanded = false
    @Published var tab: IslandTab = .player
    var pinnedExpanded = false

    // Lecture
    @Published var track: Track?
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var accent: Color = .white
    @Published var lyrics: [LyricLine] = []
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    private(set) var positionAnchor: Double = 0
    private(set) var anchorDate = Date()
    weak var controls: PlaybackControls?
    var openSettings: (() -> Void)?
    var copyClip: ((ClipItem) -> Void)?

    // Système
    @Published var battery: BatteryState?
    @Published var activity: Activity?
    private var activityDismiss: DispatchWorkItem?

    // Agenda, météo, étagère
    @Published var events: [AgendaEvent] = []
    @Published var weather: WeatherInfo?
    @Published var clipboard: [ClipItem] = []
    @Published var shelf: [URL] = [] {
        didSet { UserDefaults.standard.set(shelf.map(\.path), forKey: "shelf") }
    }

    // Minuteur et chrono
    @Published var timerEnd: Date?
    @Published var timerTotal: Double = 0
    @Published var stopwatchStart: Date?
    @Published var stopwatchAccumulated: Double = 0
    private var timerFire: DispatchWorkItem?

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: "shelf") ?? []
        shelf = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Mode et tailles

    static let flare: CGFloat = 8 // évasement des coins supérieurs

    var timerRunning: Bool { timerEnd != nil }
    var stopwatchRunning: Bool { stopwatchStart != nil }

    var mode: Mode {
        if isExpanded { return .expanded }
        if activity != nil { return .activity }
        // L'île reste visible en pause : elle ne se replie que lorsqu'il n'y a plus de morceau.
        if track != nil || timerRunning || stopwatchRunning { return .live }
        return .idle
    }

    var currentSize: CGSize { size(for: mode) }

    func size(for mode: Mode) -> CGSize {
        let n = notchSize
        let f = Self.flare * 2
        switch mode {
        case .idle:
            return CGSize(width: n.width + f, height: n.height)
        case .live:
            let side: CGFloat = (timerRunning || stopwatchRunning) ? 62 : 46
            return CGSize(width: n.width + 2 * side + f, height: n.height)
        case .activity:
            return CGSize(width: n.width + 2 * 104 + f, height: n.height)
        case .expanded:
            return CGSize(width: max(n.width + 2 * 176, 580) + f, height: n.height + 156)
        }
    }

    // MARK: - Position de lecture interpolée

    func setPosition(_ seconds: Double) {
        positionAnchor = seconds
        anchorDate = Date()
    }

    func position(at date: Date = Date()) -> Double {
        guard let track else { return 0 }
        let p = isPlaying ? positionAnchor + date.timeIntervalSince(anchorDate) : positionAnchor
        return min(max(p, 0), track.duration > 0 ? track.duration : p)
    }

    /// Avancement (0…1) dans la ligne de paroles en cours, pour le remplissage progressif.
    func lyricProgress(at date: Date = Date()) -> Double {
        guard let i = currentLyricIndex(at: date) else { return 0 }
        let start = lyrics[i].time
        let end = i + 1 < lyrics.count ? lyrics[i + 1].time : start + 4
        guard end > start else { return 1 }
        return min(1, max(0, (position(at: date) + 0.25 - start) / (end - start)))
    }

    func currentLyricIndex(at date: Date = Date()) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        let p = position(at: date) + 0.25 // légère avance pour compenser l'animation
        var idx: Int?
        for (i, line) in lyrics.enumerated() {
            if line.time <= p { idx = i } else { break }
        }
        return idx
    }

    // MARK: - Activités temporaires

    func show(_ activity: Activity, for seconds: Double = 3.5) {
        activityDismiss?.cancel()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { self.activity = activity }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { self?.activity = nil }
        }
        activityDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Minuteur

    func timerRemaining(at date: Date = Date()) -> Double {
        guard let end = timerEnd else { return 0 }
        return max(0, end.timeIntervalSince(date))
    }

    func startTimer(minutes: Double) {
        timerTotal = minutes * 60
        scheduleTimer(end: Date().addingTimeInterval(timerTotal))
        Haptics.tap()
    }

    func addTimerMinute() {
        guard let end = timerEnd else { return startTimer(minutes: 1) }
        timerTotal += 60
        scheduleTimer(end: end.addingTimeInterval(60))
    }

    func cancelTimer() {
        timerFire?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { timerEnd = nil }
    }

    private func scheduleTimer(end: Date) {
        timerFire?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { timerEnd = end }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cancelTimer()
            NSSound(named: "Glass")?.play()
            Haptics.tap(.levelChange)
            self.show(.message(symbol: "timer", text: "Minuteur terminé", detail: "", tint: .orange), for: 5)
        }
        timerFire = work
        DispatchQueue.main.asyncAfter(deadline: .now() + end.timeIntervalSinceNow, execute: work)
    }

    // MARK: - Chrono

    func stopwatchElapsed(at date: Date = Date()) -> Double {
        stopwatchAccumulated + (stopwatchStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleStopwatch() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let start = stopwatchStart {
                stopwatchAccumulated += Date().timeIntervalSince(start)
                stopwatchStart = nil
            } else {
                stopwatchStart = Date()
            }
        }
        Haptics.tap()
    }

    func resetStopwatch() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            stopwatchStart = nil
            stopwatchAccumulated = 0
        }
    }

    // MARK: - Étagère

    func addToShelf(_ urls: [URL]) {
        let new = urls.filter { url in !shelf.contains(url) }
        guard !new.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shelf.append(contentsOf: new) }
        Haptics.tap()
    }

    func removeFromShelf(_ url: URL) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { shelf.removeAll { $0 == url } }
    }
}

/// Format « m:ss » ou « h:mm:ss ».
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let t = Int(seconds.rounded(.down))
    if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
    return String(format: "%d:%02d", t / 60, t % 60)
}
