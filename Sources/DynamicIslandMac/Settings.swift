import AppKit
import ServiceManagement
import SwiftUI

enum IslandTheme: String, CaseIterable, Identifiable {
    case black = "Noir"
    case glass = "Verre"
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
    @Published var lockScreenBigArt: Bool { didSet { defaults.set(lockScreenBigArt, forKey: "lockScreenBigArt") } }
    @Published var launchAtLoginError: String?

    private init() {
        defaults.register(defaults: [
            "theme": IslandTheme.black.rawValue, "hoverDelay": 0.08, "preferMainScreen": false,
            "chargeAlerts": true, "bluetoothAlerts": true, "volumeHUD": true, "haptics": true,
            "roundedCorners": false, "cornerRadius": 10.0, "showCalendar": true, "showWeather": true,
            "weatherCity": "", "lockScreen": true, "lockScreenBigArt": false,
        ])
        lockScreen = defaults.bool(forKey: "lockScreen")
        lockScreenBigArt = defaults.bool(forKey: "lockScreenBigArt")
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

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: .shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Réglages de Dynamic Island Mac"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
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
                Toggle("Afficher sur l'écran principal", isOn: $settings.preferMainScreen)
                Toggle("Retour haptique", isOn: $settings.haptics)
            }

            Section("Île") {
                Picker("Apparence de l'île ouverte", selection: $settings.theme) {
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

            Section("Notifications dans l'île") {
                Toggle("Chargeur et batterie faible", isOn: $settings.chargeAlerts)
                Toggle("Écouteurs Bluetooth", isOn: $settings.bluetoothAlerts)
                Toggle("Volume", isOn: $settings.volumeHUD)
            }

            Section("Écran verrouillé") {
                Toggle("Lecteur et widgets sur l'écran verrouillé", isOn: $settings.lockScreen)
                Toggle("Grande pochette", isOn: $settings.lockScreenBigArt)
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
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
