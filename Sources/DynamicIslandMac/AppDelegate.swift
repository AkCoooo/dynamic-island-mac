import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = NotchModel()
    private var notch: NotchWindowController?
    private var nowPlaying: NowPlayingService?
    private var power: PowerMonitor?
    private var bluetooth: BluetoothMonitor?
    private var volume: VolumeMonitor?
    private var corners: CornerOverlayController?
    private var calendar: CalendarService?
    private var weather: WeatherService?
    private var lockScreen: LockScreenController?
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--preview-expanded` garde l'île ouverte (utile pour les captures d'écran).
        model.pinnedExpanded = CommandLine.arguments.contains("--preview-expanded")
        model.isExpanded = model.pinnedExpanded

        let nowPlaying = NowPlayingService(model: model)
        self.nowPlaying = nowPlaying
        model.controls = nowPlaying

        notch = NotchWindowController(model: model)
        power = PowerMonitor(model: model)
        bluetooth = BluetoothMonitor(model: model)
        volume = VolumeMonitor(model: model)
        corners = CornerOverlayController()
        calendar = CalendarService(model: model)
        weather = WeatherService(model: model)
        lockScreen = LockScreenController(model: model)
        setupStatusItem()

        AppSettings.shared.$preferMainScreen.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.notch?.reposition() }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island Mac")

        let menu = NSMenu()
        menu.addItem(withTitle: "Réglages…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Aperçu de l'écran verrouillé", action: #selector(previewLockScreen),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Dynamic Island Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func previewLockScreen() { lockScreen?.togglePreview() }
}
