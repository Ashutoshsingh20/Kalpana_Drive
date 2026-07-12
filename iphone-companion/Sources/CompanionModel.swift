import Combine
import CoreLocation
import Foundation
import MapKit
import Network
import UIKit

@MainActor
final class CompanionModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var battery = "Checking"
    @Published private(set) var network = "Checking"
    @Published private(set) var locationPermission = "Not requested"
    @Published private(set) var searchResults: [PhoneSearchResult] = []
    @Published private(set) var isSearching = false
    @Published var query = ""
    @Published var errorMessage: String?

    let nearby = NearbyIPadService()
    private let locationManager = CLLocationManager()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.kalpana.drive.phone.network")

    override init() {
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        locationManager.delegate = self
        refreshBattery()
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery() }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.network = path.status == .satisfied ? "Online" : "Offline"
            }
        }
        pathMonitor.start(queue: monitorQueue)
        updateLocationPermission()
    }

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }

    func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            errorMessage = "Enter at least two characters."
            return
        }
        Task {
            isSearching = true
            defer { isSearching = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = [.address, .pointOfInterest]
            do {
                let response = try await MKLocalSearch(request: request).start()
                searchResults = response.mapItems.prefix(8).map(PhoneSearchResult.init)
                errorMessage = searchResults.isEmpty ? "No destinations matched that search." : nil
            } catch {
                searchResults = []
                errorMessage = "Destination search failed: \(error.localizedDescription)"
            }
        }
    }

    func share(_ result: PhoneSearchResult) {
        do {
            try nearby.send(destination: result.payload)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateLocationPermission()
    }

    private func updateLocationPermission() {
        locationPermission = switch locationManager.authorizationStatus {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using app"
        @unknown default: "Unknown"
        }
    }

    private func refreshBattery() {
        let level = UIDevice.current.batteryLevel
        battery = level >= 0 ? "\(Int((level * 100).rounded()))%" : "Unavailable"
    }
}

struct PhoneSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D

    init(mapItem: MKMapItem) {
        name = mapItem.name ?? "Unnamed place"
        address = mapItem.placemark.title ?? "Address unavailable"
        coordinate = mapItem.placemark.coordinate
    }

    var payload: SharedDestinationPayload {
        SharedDestinationPayload(name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

