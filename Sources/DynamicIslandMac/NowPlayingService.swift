import AppKit
import SwiftUI

/// Suit Spotify et Musique.
///
/// - Les changements arrivent par notifications distribuées (aucune permission requise).
/// - La position, la pochette et les commandes passent par AppleScript
///   (macOS demande une fois l'autorisation « Automatisation »).
/// - Aucun script n'est envoyé à une app fermée : AppleScript la lancerait.
final class NowPlayingService: PlaybackControls {
    private let model: NotchModel
    private let scriptQueue = DispatchQueue(label: "dynamicislandmac.applescript", qos: .userInitiated)
    private let lyrics = LyricsService()
    private var resyncTimer: Timer?
    private var activeSource: PlayerSource?
    private var lastArtworkTrackID: String?

    init(model: NotchModel) {
        self.model = model
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                        object: nil, queue: .main) { [weak self] note in
            self?.handle(note, source: .spotify)
        }
        dnc.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"),
                        object: nil, queue: .main) { [weak self] note in
            self?.handle(note, source: .music)
        }

        // État initial, puis recalage périodique de la position (dérive, saut dans le morceau).
        refresh(.spotify)
        refresh(.music)
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.model.isPlaying, let source = self.activeSource else { return }
            self.refresh(source)
        }
    }

    // MARK: - Notifications

    private func handle(_ note: Notification, source: PlayerSource) {
        let state = (note.userInfo?["Player State"] as? String)?.lowercased() ?? ""
        if state == "playing" || activeSource == nil || activeSource == source {
            refresh(source)
        }
    }

    // MARK: - Lecture de l'état

    private func isRunning(_ source: PlayerSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    func refresh(_ source: PlayerSource) {
        guard isRunning(source) else {
            if activeSource == source { clear() }
            return
        }
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application id "com.spotify.client"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, duration of t, player position, id of t, artwork url of t}
            end tell
            """
        case .music:
            script = """
            tell application id "com.apple.Music"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, duration of t, player position, (persistent ID of t) as string, ""}
            end tell
            """
        }

        runScript(script) { [weak self] result in
            guard let self else { return }
            guard let result, let state = result.atIndex(1)?.stringValue else { return }

            if state == "stopped" || result.numberOfItems < 8 {
                if self.activeSource == source { self.clear() }
                return
            }

            let playing = state == "playing"
            // Un lecteur en pause ne prend pas la main sur un lecteur qui joue.
            if !playing, let active = self.activeSource, active != source, self.model.isPlaying { return }

            var duration = result.atIndex(5)?.doubleValue ?? 0
            if source == .spotify { duration /= 1000 } // Spotify : millisecondes
            let track = Track(
                id: result.atIndex(7)?.stringValue ?? UUID().uuidString,
                title: result.atIndex(2)?.stringValue ?? "",
                artist: result.atIndex(3)?.stringValue ?? "",
                album: result.atIndex(4)?.stringValue ?? "",
                duration: duration,
                source: source
            )
            let position = result.atIndex(6)?.doubleValue ?? 0
            let artworkURL = result.atIndex(8)?.stringValue

            self.activeSource = source
            let changed = self.model.track?.id != track.id
            self.model.setPosition(position)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.model.track = track
                self.model.isPlaying = playing
            }
            if changed { self.trackChanged(track, artworkURL: artworkURL) }
        }
    }

    private func clear() {
        activeSource = nil
        lastArtworkTrackID = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            model.track = nil
            model.isPlaying = false
            model.artwork = nil
            model.lyrics = []
            model.accent = .white
        }
    }

    // MARK: - Pochette et paroles

    private func trackChanged(_ track: Track, artworkURL: String?) {
        model.lyrics = []
        lyrics.fetch(for: track) { [weak self] lines in
            guard let self, self.model.track?.id == track.id else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.model.lyrics = lines }
        }
        loadArtwork(for: track, spotifyURL: artworkURL)
    }

    private func loadArtwork(for track: Track, spotifyURL: String?) {
        guard lastArtworkTrackID != track.id else { return }
        lastArtworkTrackID = track.id

        let apply: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.model.track?.id == track.id else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.model.artwork = image
                    self.model.accent = image?.accentColor() ?? .white
                }
            }
        }

        switch track.source {
        case .spotify:
            if let s = spotifyURL, let url = URL(string: s) {
                Artwork.download(url) { apply($0) }
            } else {
                Artwork.searchITunes(track) { apply($0) }
            }
        case .music:
            let script = """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """
            runScript(script) { result in
                if let data = result?.data, let image = NSImage(data: data) {
                    apply(image)
                } else {
                    Artwork.searchITunes(track) { apply($0) }
                }
            }
        }
    }

    // MARK: - Commandes

    func togglePlayPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command("previous track") }

    func seek(to seconds: Double) {
        model.setPosition(seconds)
        command("set player position to \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds))")
    }

    private func command(_ verb: String) {
        guard let source = activeSource, isRunning(source) else { return }
        runScript("tell application id \"\(source.bundleID)\" to \(verb)") { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refresh(source) }
        }
    }

    // MARK: - AppleScript

    private func runScript(_ source: String, completion: @escaping (NSAppleEventDescriptor?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { NSLog("Dynamic Island Mac AppleScript: \(error)") }
            DispatchQueue.main.async { completion(error == nil ? result : nil) }
        }
    }
}

// MARK: - Pochettes

enum Artwork {
    static func download(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            completion(data.flatMap { NSImage(data: $0) })
        }.resume()
    }

    /// Repli : pochette via l'API publique de recherche iTunes.
    static func searchITunes(_ track: Track, completion: @escaping (NSImage?) -> Void) {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = c.url else { return completion(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let small = first["artworkUrl100"] as? String,
                  let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
            else { return completion(nil) }
            download(big, completion: completion)
        }.resume()
    }
}

extension NSImage {
    /// Couleur moyenne de la pochette, éclaircie pour rester lisible sur fond noir.
    func accentColor() -> Color? {
        guard let tiff = tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: input.extent),
              ]),
              let output = filter.outputImage
        else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(output, toBitmap: &pixel, rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let base = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(nsColor: NSColor(hue: h, saturation: min(1, s * 1.25), brightness: max(b, 0.82), alpha: 1))
    }
}
