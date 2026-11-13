import AppKit
import CoreBluetooth
import IOBluetooth
import IOKit.ps

// MARK: - Batterie et recharge

/// Écoute les changements d'alimentation via IOKit (API publique, sans permission).
final class PowerMonitor {
    private let model: NotchModel
    private var runLoopSource: CFRunLoopSource?
    private var lastWarnedLevel: Int?

    init(model: NotchModel) {
        self.model = model
        model.battery = Self.read()

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().changed()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    private func changed() {
        guard let new = Self.read() else { return }
        let old = model.battery
        model.battery = new
        guard AppSettings.shared.chargeAlerts else { return }

        if let old, !old.pluggedIn, new.pluggedIn {
            model.show(.power(new))
            Haptics.tap(.levelChange)
        }
        // Alerte unique à 20 % puis à 10 %.
        if !new.pluggedIn, let level = [20, 10].first(where: { new.percent <= $0 }), lastWarnedLevel != level {
            lastWarnedLevel = level
            model.show(.power(new), for: 5)
        }
        if new.pluggedIn { lastWarnedLevel = nil }
    }

    static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryState(
                percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                pluggedIn: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            )
        }
        return nil
    }
}

// MARK: - Écouteurs Bluetooth

/// Affiche la connexion d'un casque ou d'AirPods.
/// La batterie des AirPods n'a pas d'API publique : on la lit seulement si
/// IOBluetooth l'expose sur l'appareil, sinon on affiche « Connecté ».
final class BluetoothMonitor: NSObject, CBCentralManagerDelegate {
    private let model: NotchModel
    private var startedAt = Date()
    private var connectNotification: IOBluetoothUserNotification?
    private var central: CBCentralManager?

    /// IOBluetooth bloque le thread principal tant que l'autorisation Bluetooth n'est pas tranchée :
    /// on la demande d'abord, sans bloquer, via Core Bluetooth, et on n'écoute IOBluetooth qu'une fois accordée.
    init(model: NotchModel) {
        self.model = model
        super.init()
        switch CBManager.authorization {
        case .allowedAlways:
            startListening()
        case .notDetermined:
            central = CBCentralManager(delegate: self, queue: .main) // affiche la demande, sans bloquer
        default:
            debugLog("bluetooth: autorisation refusée, notifications d'écouteurs désactivées")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard CBManager.authorization == .allowedAlways, connectNotification == nil else { return }
        startListening()
    }

    private func startListening() {
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Self.isAudio(device) else { return }
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Au démarrage, IOBluetooth signale aussi les appareils déjà connectés : on les ignore.
        guard Date().timeIntervalSince(startedAt) > 3, AppSettings.shared.bluetoothAlerts else { return }

        let name = device.name ?? "Écouteurs"
        // La batterie arrive parfois une à deux secondes après la connexion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.model.show(.headphones(name: name, symbol: Self.symbol(for: name),
                                         battery: Self.battery(of: device), connected: true), for: 4)
            Haptics.tap()
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard AppSettings.shared.bluetoothAlerts else { return }
        let name = device.name ?? "Écouteurs"
        model.show(.headphones(name: name, symbol: Self.symbol(for: name), battery: nil, connected: false), for: 2.5)
    }

    private static func isAudio(_ device: IOBluetoothDevice) -> Bool {
        device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
            || (device.name ?? "").localizedCaseInsensitiveContains("airpods")
    }

    private static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    private static func battery(of device: IOBluetoothDevice) -> Int? {
        for key in ["batteryPercentCombined", "batteryPercentSingle", "batteryPercentLeft"]
        where device.responds(to: NSSelectorFromString(key)) {
            if let value = device.value(forKey: key) as? Int, value > 0, value <= 100 { return value }
        }
        return nil
    }
}
