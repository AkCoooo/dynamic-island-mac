import Foundation

/// Journal de diagnostic dans ~/Library/Logs/DynamicIslandMac.log (lisible avec Console.app).
func debugLog(_ message: String) {
    NSLog("%@", message)
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DynamicIslandMac.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}
