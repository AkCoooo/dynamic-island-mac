import AppKit
import Combine
import CoreLocation
import EventKit
import SwiftUI

// MARK: - Agenda

/// Prochains événements des calendriers (EventKit, accès demandé une fois).
final class CalendarService {
    private let model: NotchModel
    private let store = EKEventStore()
    private var timer: Timer?
    private var granted = false
    private var cancellables: Set<AnyCancellable> = []

    init(model: NotchModel) {
        self.model = model
        AppSettings.shared.$showCalendar
            .receive(on: RunLoop.main)
            .sink { [weak self] on in on ? self?.start() : self?.stop() }
            .store(in: &cancellables)
    }

    private func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.granted = granted
                guard granted else { return }
                self.refresh()
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: self.store,
                                                       queue: .main) { [weak self] _ in self?.refresh() }
                self.timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                    self?.refresh()
                }
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        model.events = []
    }

    func refresh() {
        guard granted, AppSettings.shared.showCalendar else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now))!
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .prefix(6)
            .map { e in
                AgendaEvent(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "Sans titre",
                            start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                            color: Color(nsColor: e.calendar.color ?? .systemBlue))
            }
        model.events = Array(events)
    }
}

// MARK: - Météo

/// Météo actuelle via Open-Meteo (gratuit, sans clé).
/// Position : la ville des réglages, sinon Core Location.
final class WeatherService: NSObject, CLLocationManagerDelegate {
    private let model: NotchModel
    private let location = CLLocationManager()
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var lastCoordinate: CLLocationCoordinate2D?

    init(model: NotchModel) {
        self.model = model
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        let settings = AppSettings.shared
        settings.$showWeather.combineLatest(settings.$weatherCity.debounce(for: .seconds(1), scheduler: RunLoop.main))
            .receive(on: RunLoop.main)
            .sink { [weak self] on, _ in on ? self?.refresh() : (self?.model.weather = nil) }
            .store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard AppSettings.shared.showWeather else { return }
        let city = AppSettings.shared.weatherCity.trimmingCharacters(in: .whitespaces)
        if city.isEmpty {
            switch location.authorizationStatus {
            case .notDetermined: location.requestWhenInUseAuthorization()
            case .denied, .restricted: break
            default: location.requestLocation()
            }
        } else {
            geocode(city)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)) { [weak self] p, _ in
            self?.fetch(c, place: p?.first?.locality ?? "")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("Dynamic Island Mac météo : position indisponible (\(error.localizedDescription))")
    }

    private func geocode(_ city: String) {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"),
                        URLQueryItem(name: "language", value: "fr")]
        getJSON(c.url) { [weak self] json in
            guard let first = (json?["results"] as? [[String: Any]])?.first,
                  let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double
            else { return }
            self?.fetch(CLLocationCoordinate2D(latitude: lat, longitude: lon), place: first["name"] as? String ?? city)
        }
    }

    private func fetch(_ coordinate: CLLocationCoordinate2D, place: String) {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        getJSON(c.url) { [weak self] json in
            guard let current = json?["current"] as? [String: Any],
                  let temp = current["temperature_2m"] as? Double,
                  let code = current["weather_code"] as? Int
            else { return }
            let daily = json?["daily"] as? [String: Any]
            let high = (daily?["temperature_2m_max"] as? [Double])?.first ?? temp
            let low = (daily?["temperature_2m_min"] as? [Double])?.first ?? temp
            let isDay = (current["is_day"] as? Int ?? 1) == 1
            let (symbol, label) = Self.describe(code, isDay: isDay)
            DispatchQueue.main.async {
                self?.model.weather = WeatherInfo(temperature: Int(temp.rounded()), high: Int(high.rounded()),
                                                  low: Int(low.rounded()), symbol: symbol, label: label, place: place)
            }
        }
    }

    private func getJSON(_ url: URL?, completion: @escaping ([String: Any]?) -> Void) {
        guard let url else { return completion(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            completion(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }.resume()
    }

    /// Codes météo WMO utilisés par Open-Meteo.
    static func describe(_ code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0: return (isDay ? "sun.max.fill" : "moon.stars.fill", "Dégagé")
        case 1, 2: return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Éclaircies")
        case 3: return ("cloud.fill", "Couvert")
        case 45, 48: return ("cloud.fog.fill", "Brouillard")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Bruine")
        case 61, 63, 65, 66, 67, 80, 81, 82: return ("cloud.rain.fill", "Pluie")
        case 71, 73, 75, 77, 85, 86: return ("cloud.snow.fill", "Neige")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "Orage")
        default: return ("cloud.fill", "—")
        }
    }
}
