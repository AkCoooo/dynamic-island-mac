import Foundation

/// Paroles synchronisées depuis LRCLIB (https://lrclib.net), API publique et gratuite.
final class LyricsService {
    private var cache: [String: [LyricLine]] = [:]

    func fetch(for track: Track, completion: @escaping ([LyricLine]) -> Void) {
        let key = "\(track.artist)|\(track.title)"
        if let cached = cache[key] { return completion(cached) }

        get(track) { [weak self] lines in
            if let lines, !lines.isEmpty {
                self?.finish(key, lines, completion)
            } else {
                self?.search(track) { self?.finish(key, $0 ?? [], completion) }
            }
        }
    }

    private func finish(_ key: String, _ lines: [LyricLine], _ completion: @escaping ([LyricLine]) -> Void) {
        DispatchQueue.main.async {
            self.cache[key] = lines
            completion(lines)
        }
    }

    /// Correspondance exacte (artiste, titre, album, durée).
    private func get(_ track: Track, completion: @escaping ([LyricLine]?) -> Void) {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: Self.cleanTitle(track.title)),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        request(c.url) { json in
            completion((json as? [String: Any]).flatMap { Self.parse($0["syncedLyrics"] as? String) })
        }
    }

    /// Recherche plus large si la correspondance exacte échoue.
    private func search(_ track: Track, completion: @escaping ([LyricLine]?) -> Void) {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: Self.cleanTitle(track.title)),
        ]
        request(c.url) { json in
            let results = json as? [[String: Any]] ?? []
            let synced = results.lazy.compactMap { $0["syncedLyrics"] as? String }.first
            completion(Self.parse(synced))
        }
    }

    private func request(_ url: URL?, completion: @escaping (Any?) -> Void) {
        guard let url else { return completion(nil) }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("DynamicIslandMac/0.1 (macOS notch app)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return completion(nil) }
            completion(try? JSONSerialization.jsonObject(with: data))
        }.resume()
    }

    /// Retire « - Remastered 2011 », « (feat. X) », etc.
    static func cleanTitle(_ title: String) -> String {
        var t = title
        for pattern in [#"\s+-\s+.*(remaster|version|edit|live|mono|stereo).*$"#,
                        #"\s*[\(\[](feat\.|ft\.|with ).*?[\)\]]"#] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Format LRC : « [mm:ss.xx] texte », plusieurs horodatages possibles par ligne.
    static func parse(_ lrc: String?) -> [LyricLine]? {
        guard let lrc, !lrc.isEmpty else { return nil }
        let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                lines.append(LyricLine(time: min * 60 + sec, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
