import Foundation
import CoreLocation

struct WeatherSnapshot: Equatable {
    var temperature: Double = 0
    var apparent: Double = 0
    var code: Int = -1
    var isDay: Bool = true
    var high: Double = 0
    var low: Double = 0
    var place: String = ""
    var updatedAt: Date = .distantPast
    var available: Bool = false

    var symbol: String {
        switch code {
        case 0:        return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:     return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:        return "cloud.fill"
        case 45, 48:   return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default:       return "thermometer.medium"
        }
    }

    var summary: String {
        switch code {
        case 0:        return "Clear"
        case 1:        return "Mostly clear"
        case 2:        return "Partly cloudy"
        case 3:        return "Overcast"
        case 45, 48:   return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57:   return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67:   return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86:   return "Snow showers"
        case 95:       return "Thunderstorm"
        case 96, 99:   return "Thunderstorm, hail"
        default:       return "Unknown"
        }
    }

    func formatted(_ value: Double, fahrenheit: Bool) -> String {
        let converted = fahrenheit ? value * 9 / 5 + 32 : value
        return "\(Int(converted.rounded()))°"
    }
}

@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    @Published private(set) var snapshot = WeatherSnapshot()
    @Published private(set) var status: String = "idle"

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var coordinate: CLLocationCoordinate2D?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        refreshLocation()
        fetch()
        let t = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        refreshLocation()
    }

    private func refreshLocation() {
        guard Prefs.shared.d.weatherUseLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            status = "location denied"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.coordinate = location.coordinate
            self.fetch()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in self.status = "location unavailable" }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refreshLocation() }
    }

    private var activeCoordinate: CLLocationCoordinate2D? {
        let prefs = Prefs.shared.d
        if !prefs.weatherUseLocation || coordinate == nil {
            guard prefs.weatherLatitude != 0 || prefs.weatherLongitude != 0 else {
                return coordinate
            }
            return CLLocationCoordinate2D(latitude: prefs.weatherLatitude,
                                          longitude: prefs.weatherLongitude)
        }
        return coordinate
    }

    func fetch() {
        guard Prefs.shared.d.showWeather else { return }
        guard let coordinate = activeCoordinate else {
            status = "no location set"
            return
        }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,"
                         + "weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = components.url else { return }

        Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let root = try JSONSerialization.jsonObject(with: data)
                          as? [String: Any] else {
                    await MainActor.run { self?.status = "service unavailable" }
                    return
                }
                let current = root["current"] as? [String: Any] ?? [:]
                let daily = root["daily"] as? [String: Any] ?? [:]

                var snap = WeatherSnapshot()
                snap.temperature = current["temperature_2m"] as? Double ?? 0
                snap.apparent = current["apparent_temperature"] as? Double ?? snap.temperature
                snap.code = current["weather_code"] as? Int ?? -1
                snap.isDay = (current["is_day"] as? Int ?? 1) == 1
                snap.high = (daily["temperature_2m_max"] as? [Double])?.first ?? 0
                snap.low = (daily["temperature_2m_min"] as? [Double])?.first ?? 0
                snap.updatedAt = .now
                snap.available = true

                await MainActor.run {
                    self?.snapshot = snap
                    self?.status = "ok"
                }
                await self?.resolvePlace(coordinate)
            } catch {
                await MainActor.run { self?.status = "offline" }
            }
        }
    }

    private func resolvePlace(_ coordinate: CLLocationCoordinate2D) async {
        guard snapshot.place.isEmpty else { return }
        let location = CLLocation(latitude: coordinate.latitude,
                                  longitude: coordinate.longitude)
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let name = marks.first?.locality ?? marks.first?.administrativeArea else { return }
        snapshot.place = name
    }
}
