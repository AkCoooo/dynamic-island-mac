import AppKit

if MainActor.assumeIsolated({ Snapshot.runIfRequested() }) { exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
