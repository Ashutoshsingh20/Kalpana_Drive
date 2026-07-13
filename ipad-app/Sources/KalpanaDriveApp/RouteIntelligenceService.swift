import Foundation
import CoreLocation
import CoreMotion
import KalpanaDriveCore

@MainActor
final class RouteIntelligenceService: ObservableObject {
    @Published private(set) var roadPreferences: [PersonalRoadPreference] = []
    @Published var ignisFuelType: IgnisFuelType = .petrol
    @Published var ignisEstimatedRangeKM: Double = 350
    @Published var avoidNarrowRoads = false
    @Published var preferWiderRoads = false
    @Published var avoidTolls = false
    @Published var avoidHighways = false
    
    @Published private(set) var detectedPotholes: [Coordinate] = []
    private let motionManager = CMMotionManager()
    private let repository: RoutePreferenceRepository

    enum IgnisFuelType: String, Codable, CaseIterable, Identifiable {
        case petrol = "Petrol"
        case cng = "CNG"
        case biFuel = "Petrol + CNG"
        var id: Self { self }
    }

    init(repository: RoutePreferenceRepository? = nil) {
        self.repository = repository ?? JSONRoutePreferenceRepository(fileURL: Self.defaultPrefsURL)
        Task {
            self.roadPreferences = await self.repository.loadRoadPreferences()
            self.avoidTolls = await self.repository.loadAvoidTolls()
            self.avoidHighways = await self.repository.loadAvoidHighways()
        }
        setupMotionDetection()
    }

    func setAvoidTolls(_ avoid: Bool) {
        self.avoidTolls = avoid
        Task { try? await repository.setAvoidTolls(avoid) }
    }

    func setAvoidHighways(_ avoid: Bool) {
        self.avoidHighways = avoid
        Task { try? await repository.setAvoidHighways(avoid) }
    }

    func avoidRoad(_ roadName: String) {
        let pref = PersonalRoadPreference(roadName: roadName, preferenceType: .avoid)
        roadPreferences.removeAll(where: { $0.roadName == roadName })
        roadPreferences.append(pref)
        Task { try? await repository.saveRoadPreference(pref) }
    }

    func preferRoad(_ roadName: String) {
        let pref = PersonalRoadPreference(roadName: roadName, preferenceType: .prefer)
        roadPreferences.removeAll(where: { $0.roadName == roadName })
        roadPreferences.append(pref)
        Task { try? await repository.saveRoadPreference(pref) }
    }

    func deleteRoadPreference(_ roadName: String) {
        roadPreferences.removeAll(where: { $0.roadName == roadName })
        Task { try? await repository.deleteRoadPreference(roadName: roadName) }
    }

    private func setupMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            let acceleration = data.acceleration
            let totalG = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
            if totalG > 2.5 {
                // Pothole or rough road detected
            }
        }
    }

    func addPotholeObservation(_ coord: Coordinate) {
        detectedPotholes.append(coord)
    }

    func clearPotholes() {
        detectedPotholes = []
    }

    private static var defaultPrefsURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("KalpanaDrive/route-preferences.json")
    }
}
