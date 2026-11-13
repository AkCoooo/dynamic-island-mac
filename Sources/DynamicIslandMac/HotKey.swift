import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Raccourci clavier global, via l'API Carbon `RegisterEventHotKey`.
/// Il marche dans toutes les apps et ne demande aucune autorisation (ni Accessibilité, ni clavier).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    var action: (() -> Void)?

    private init() {}

    /// Enregistre le raccourci des réglages ; un code négatif le désactive.
    func apply(keyCode: Int, modifiers: Int) {
        unregister()
        guard keyCode >= 0 else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4449_4D43), id: 1) // « DIMC »
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        debugLog("raccourci: enregistrement \(AppSettings.shared.clipboardHotKeyLabel) → \(status)")
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.shared.action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    // MARK: - Conversion des touches

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return m
    }

    static func label(for event: NSEvent) -> String {
        let f = event.modifierFlags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        let special: [Int: String] = [
            kVK_Space: "Espace", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(event.keyCode)] { return s + name }
        return s + (event.charactersIgnoringModifiers?.uppercased() ?? "?")
    }
}

/// Bouton qui enregistre un raccourci : clic, puis la combinaison voulue. Échap annule.
struct ShortcutRecorder: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var refused = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? "Tape le raccourci…" : (settings.clipboardHotKeyCode < 0 ? "Aucun" : settings.clipboardHotKeyLabel))
                    .frame(minWidth: 130)
                    .foregroundStyle(recording ? Color.accentColor : .primary)
            }
            if !recording && settings.clipboardHotKeyCode >= 0 {
                Button { settings.clipboardHotKeyCode = -1 } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Supprimer le raccourci")
            }
        }
        .onDisappear(perform: stop)
        .help(refused ? "Il faut au moins ⌘, ⌥ ou ⌃ dans le raccourci." : "")
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.unregister() // sinon le raccourci actuel se déclencherait pendant l'enregistrement
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape { stop(); return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            guard !mods.isEmpty else { refused = true; NSSound.beep(); return nil }
            refused = false
            settings.clipboardHotKeyLabel = HotKeyCenter.label(for: event)
            settings.clipboardHotKeyMods = HotKeyCenter.carbonModifiers(event.modifierFlags)
            settings.clipboardHotKeyCode = Int(event.keyCode)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyCenter.shared.apply(keyCode: settings.clipboardHotKeyCode, modifiers: settings.clipboardHotKeyMods)
        }
    }
}
