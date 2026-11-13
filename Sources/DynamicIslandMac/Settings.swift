import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

enum IslandTheme: String, CaseIterable, Identifiable {
    case black = "Noir"
    case glass = "Verre"
    case light = "Clair"
    var id: String { rawValue }
}

enum LockScreenStyle: String, CaseIterable, Identifiable {
    case fullScreen = "Plein écran"
    case bigArt = "Grande pochette"
    case card = "Carte"
    var id: String { rawValue }
}

/// Réglages persistés dans UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var theme: IslandTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var preferMainScreen: Bool { didSet { defaults.set(preferMainScreen, forKey: "preferMainScreen") } }
    @Published var chargeAlerts: Bool { didSet { defaults.set(chargeAlerts, forKey: "chargeAlerts") } }
    @Published var bluetoothAlerts: Bool { didSet { defaults.set(bluetoothAlerts, forKey: "bluetoothAlerts") } }
    @Published var volumeHUD: Bool { didSet { defaults.set(volumeHUD, forKey: "volumeHUD") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    @Published var roundedCorners: Bool { didSet { defaults.set(roundedCorners, forKey: "roundedCorners") } }
    @Published var cornerRadius: Double { didSet { defaults.set(cornerRadius, forKey: "cornerRadius") } }
    @Published var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: "showCalendar") } }
    @Published var showWeather: Bool { didSet { defaults.set(showWeather, forKey: "showWeather") } }
    @Published var weatherCity: String { didSet { defaults.set(weatherCity, forKey: "weatherCity") } }
    @Published var lockScreen: Bool { didSet { defaults.set(lockScreen, forKey: "lockScreen") } }
    @Published var lockScreenShowPassword: Bool { didSet { defaults.set(lockScreenShowPassword, forKey: "lockScreenShowPassword") } }
    @Published var lockScreenStyle: LockScreenStyle { didSet { defaults.set(lockScreenStyle.rawValue, forKey: "lockScreenStyle") } }
    @Published var clipboardHotKeyCode: Int { didSet { defaults.set(clipboardHotKeyCode, forKey: "clipboardHotKeyCode") } }
    @Published var clipboardHotKeyMods: Int { didSet { defaults.set(clipboardHotKeyMods, forKey: "clipboardHotKeyMods") } }
    @Published var clipboardHotKeyLabel: String { didSet { defaults.set(clipboardHotKeyLabel, forKey: "clipboardHotKeyLabel") } }
    @Published var doubleCopyPopup: Bool { didSet { defaults.set(doubleCopyPopup, forKey: "doubleCopyPopup") } }
    @Published var pasteDirectly: Bool { didSet { defaults.set(pasteDirectly, forKey: "pasteDirectly") } }
    @Published var clipboardHistory: Bool { didSet { defaults.set(clipboardHistory, forKey: "clipboardHistory") } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var keepAwakeWhilePlaying: Bool { didSet { defaults.set(keepAwakeWhilePlaying, forKey: "keepAwakeWhilePlaying") } }
    @Published var progressiveLyrics: Bool { didSet { defaults.set(progressiveLyrics, forKey: "progressiveLyrics") } }
    @Published var lockScreenWidgets: Bool { didSet { defaults.set(lockScreenWidgets, forKey: "lockScreenWidgets") } }
    @Published var lockScreenOffset: Double { didSet { defaults.set(lockScreenOffset, forKey: "lockScreenOffset") } }
    @Published var launchAtLoginError: String?

    private init() {
        defaults.register(defaults: [
            "theme": IslandTheme.black.rawValue, "hoverDelay": 0.08, "preferMainScreen": false,
            "chargeAlerts": true, "bluetoothAlerts": true, "volumeHUD": true, "haptics": true,
            "roundedCorners": false, "cornerRadius": 10.0, "showCalendar": true, "showWeather": true,
            "weatherCity": "", "lockScreen": true, "lockScreenStyle": LockScreenStyle.fullScreen.rawValue, "lockScreenShowPassword": false,
            "clipboardHotKeyCode": 9, "clipboardHotKeyMods": 768, "clipboardHotKeyLabel": "⇧⌘V",
            "keepAwakeWhilePlaying": false, "showMenuBarIcon": true, "clipboardHistory": true, "doubleCopyPopup": true, "pasteDirectly": false, "progressiveLyrics": true, "lockScreenWidgets": true, "lockScreenOffset": 0.0,
        ])
        clipboardHistory = defaults.bool(forKey: "clipboardHistory")
        doubleCopyPopup = defaults.bool(forKey: "doubleCopyPopup")
        pasteDirectly = defaults.bool(forKey: "pasteDirectly")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        keepAwakeWhilePlaying = defaults.bool(forKey: "keepAwakeWhilePlaying")
        progressiveLyrics = defaults.bool(forKey: "progressiveLyrics")
        lockScreenWidgets = defaults.bool(forKey: "lockScreenWidgets")
        lockScreenOffset = defaults.double(forKey: "lockScreenOffset")
        lockScreen = defaults.bool(forKey: "lockScreen")
        lockScreenShowPassword = defaults.bool(forKey: "lockScreenShowPassword")
        lockScreenStyle = LockScreenStyle(rawValue: defaults.string(forKey: "lockScreenStyle") ?? "") ?? .fullScreen
        clipboardHotKeyCode = defaults.integer(forKey: "clipboardHotKeyCode")
        clipboardHotKeyMods = defaults.integer(forKey: "clipboardHotKeyMods")
        clipboardHotKeyLabel = defaults.string(forKey: "clipboardHotKeyLabel") ?? "⇧⌘V"
        theme = IslandTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .black
        hoverDelay = defaults.double(forKey: "hoverDelay")
        preferMainScreen = defaults.bool(forKey: "preferMainScreen")
        chargeAlerts = defaults.bool(forKey: "chargeAlerts")
        bluetoothAlerts = defaults.bool(forKey: "bluetoothAlerts")
        volumeHUD = defaults.bool(forKey: "volumeHUD")
        haptics = defaults.bool(forKey: "haptics")
        roundedCorners = defaults.bool(forKey: "roundedCorners")
        cornerRadius = defaults.double(forKey: "cornerRadius")
        showCalendar = defaults.bool(forKey: "showCalendar")
        showWeather = defaults.bool(forKey: "showWeather")
        weatherCity = defaults.string(forKey: "weatherCity") ?? ""
    }

    // MARK: - Lancement à l'ouverture de session

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
            }
        }
    }

    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}

enum Haptics {
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard AppSettings.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

// MARK: - Fenêtre de réglages

/// Fenêtre de réglages. Tant qu'elle est ouverte, l'app apparaît dans le Dock et dans ⌘⇥
/// comme une app normale ; à la fermeture, elle redevient discrète (barre des menus seulement).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var previewLockScreen: (() -> Void)?

    func show() {
        if window == nil {
            let view = SettingsView(settings: .shared,
                                    previewLockScreen: { [weak self] in self?.previewLockScreen?() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Dynamic Island Mac"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var previewLockScreen: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
        }
        .frame(width: 480, height: 660)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dynamic Island Mac").font(.title2.weight(.semibold))
                Text("Survole l'encoche pour ouvrir l'île.\nRelance l'app ou clique ⚙ dans l'île pour revenir ici.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Aperçu de l'écran verrouillé", action: previewLockScreen)
                    Button("Quitter l'app") { NSApp.terminate(nil) }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var form: some View {
        Form {
            Section("Général") {
                Toggle("Ouvrir Dynamic Island Mac à l'ouverture de session", isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                if settings.launchAtLoginNeedsApproval {
                    Text("À autoriser dans Réglages Système › Général › Ouverture.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Afficher l'icône dans la barre des menus", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Text("Pour revenir ici : relance l'app depuis le Launchpad ou Spotlight, ou clique ⚙ dans l'île.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Afficher sur l'écran principal", isOn: $settings.preferMainScreen)
                Toggle("Retour haptique", isOn: $settings.haptics)
            }

            Section("Musique") {
                Toggle("Paroles qui se remplissent au fil du chant", isOn: $settings.progressiveLyrics)
                Toggle("Garder l'écran allumé pendant la lecture", isOn: $settings.keepAwakeWhilePlaying)
            }

            Section("Île") {
                Picker("Apparence", selection: $settings.theme) {
                    ForEach(IslandTheme.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Délai d'ouverture au survol") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.02)
                        Text("\(Int(settings.hoverDelay * 1000)) ms").monospacedDigit().frame(width: 52)
                    }
                }
            }

            Section("Presse-papiers") {
                Toggle("Garder l'historique des copies", isOn: $settings.clipboardHistory)
                LabeledContent("Raccourci pour ouvrir l'historique") { ShortcutRecorder() }
                    .disabled(!settings.clipboardHistory)
                Toggle("Double ⌘C ouvre aussi l'historique", isOn: $settings.doubleCopyPopup)
                    .disabled(!settings.clipboardHistory)
                Toggle("Coller directement l'élément choisi", isOn: Binding(
                    get: { settings.pasteDirectly },
                    set: { on in
                        settings.pasteDirectly = on
                        // Simuler ⌘V demande l'autorisation Accessibilité : macOS ouvre sa demande.
                        if on && !AXIsProcessTrusted() {
                            _ = AXIsProcessTrustedWithOptions(
                                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                        }
                    }))
                    .disabled(!settings.clipboardHistory)
                if settings.pasteDirectly && !AXIsProcessTrusted() {
                    Text("Autorise Dynamic Island Mac dans Réglages Système › Confidentialité › Accessibilité. Sans ça, l'élément choisi est copié et tu colles avec ⌘V.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Les 30 dernières copies, en mémoire seulement. Les mots de passe copiés depuis un gestionnaire de mots de passe sont ignorés.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notifications dans l'île") {
                Toggle("Chargeur et batterie faible", isOn: $settings.chargeAlerts)
                Toggle("Écouteurs Bluetooth", isOn: $settings.bluetoothAlerts)
                Toggle("Volume", isOn: $settings.volumeHUD)
            }

            Section("Écran verrouillé") {
                Toggle("Lecteur et widgets sur l'écran verrouillé", isOn: $settings.lockScreen)
                Group {
                    Toggle("Widgets météo, batterie et agenda", isOn: $settings.lockScreenWidgets)
                    Picker("Style", selection: $settings.lockScreenStyle) {
                        ForEach(LockScreenStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if settings.lockScreenStyle == .fullScreen {
                        Toggle("Laisser voir le champ mot de passe en bas", isOn: $settings.lockScreenShowPassword)
                        Text("La pochette remplit tout l'écran. Même si le champ est caché, tape ton mot de passe puis ↩, ou utilise Touch ID : ça marche pareil.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Position verticale") {
                        HStack {
                            Slider(value: $settings.lockScreenOffset, in: -160...160, step: 10)
                            Button("Centrer") { settings.lockScreenOffset = 0 }.controlSize(.small)
                        }
                    }
                }
                .disabled(!settings.lockScreen)
                Text("Utilise une API privée de macOS : peut cesser de fonctionner après une mise à jour.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Écran") {
                Toggle("Arrondir les coins du bas de l'écran", isOn: $settings.roundedCorners)
                if settings.roundedCorners {
                    LabeledContent("Rayon") {
                        HStack {
                            Slider(value: $settings.cornerRadius, in: 4...24, step: 1)
                            Text("\(Int(settings.cornerRadius)) pt").monospacedDigit().frame(width: 44)
                        }
                    }
                }
            }

            Section("Agenda et météo") {
                Toggle("Afficher les prochains événements", isOn: $settings.showCalendar)
                Toggle("Afficher la météo", isOn: $settings.showWeather)
                TextField("Ville (vide : position actuelle)", text: $settings.weatherCity)
            }
        }
        .formStyle(.grouped)
    }
}
