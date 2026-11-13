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
    private var keepAwake: KeepAwake?
    private var clipboard: ClipboardMonitor?
    private var clipboardPopup: ClipboardPopupController?
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
        volume = VolumeMonitor(model: model)
        corners = CornerOverlayController()
        calendar = CalendarService(model: model)
        weather = WeatherService(model: model)
        lockScreen = LockScreenController(model: model)
        lockScreen?.refreshNowPlaying = { [weak nowPlaying] in
            nowPlaying?.refresh(.spotify)
            nowPlaying?.refresh(.music)
        }
        keepAwake = KeepAwake(model: model)
        let clipboard = ClipboardMonitor(model: model)
        self.clipboard = clipboard
        model.copyClip = { [weak clipboard] item in clipboard?.copy(item) }
        let popup = ClipboardPopupController(model: model)
        clipboardPopup = popup
        clipboard.onDoubleCopy = { [weak popup] in popup?.show() }
        HotKeyCenter.shared.action = { [weak popup] in
            guard AppSettings.shared.clipboardHistory else { return }
            popup?.show()
        }
        let settings = AppSettings.shared
        HotKeyCenter.shared.apply(keyCode: settings.clipboardHotKeyCode, modifiers: settings.clipboardHotKeyMods)
        settings.$clipboardHotKeyCode.dropFirst()
            .receive(on: RunLoop.main)
            .sink { code in HotKeyCenter.shared.apply(keyCode: code, modifiers: AppSettings.shared.clipboardHotKeyMods) }
            .store(in: &cancellables)

        // Menus et réglages suivent l'apparence choisie.
        AppSettings.shared.$theme
            .receive(on: RunLoop.main)
            .sink { theme in NSApp.appearance = NSAppearance(named: theme == .light ? .aqua : .darkAqua) }
            .store(in: &cancellables)
        setupStatusItem()
        bluetooth = BluetoothMonitor(model: model)

        // Trois accès aux réglages : le bouton ⚙ de l'île, le menu de la barre des menus,
        // et un nouveau lancement de l'app (Applications, Launchpad, Spotlight).
        model.openSettings = { [weak self] in self?.openSettings() }
        settingsWindow.previewLockScreen = { [weak self] in self?.lockScreen?.togglePreview() }

        AppSettings.shared.$showMenuBarIcon.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.statusItem?.isVisible = visible }
            .store(in: &cancellables)

        AppSettings.shared.$preferMainScreen.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.notch?.reposition() }
            .store(in: &cancellables)

        // Premier lancement : on ouvre les réglages pour montrer où ils sont.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didLaunchBefore") {
            defaults.set(true, forKey: "didLaunchBefore")
            openSettings()
        }
    }

    /// Double-clic sur l'app alors qu'elle tourne déjà : on ouvre les réglages.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        item.isVisible = AppSettings.shared.showMenuBarIcon

        let menu = NSMenu()
        menu.addItem(withTitle: "Réglages…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Aperçu de l'écran verrouillé", action: #selector(previewLockScreen),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter Dynamic Island Mac", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func previewLockScreen() { lockScreen?.togglePreview() }
}
