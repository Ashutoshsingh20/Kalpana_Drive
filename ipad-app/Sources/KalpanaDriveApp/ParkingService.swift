import Foundation
import CoreLocation
import KalpanaDriveCore

@MainActor
final class ParkingService: ObservableObject {
    @Published private(set) var currentParking: ParkedLocation?
    @Published var showsSuggestionPrompt = false
    @Published private(set) var suggestedCoordinate: Coordinate?

    private let repository: ParkingRepository
    private var lastSpeed: Double = 0

    init(repository: ParkingRepository? = nil) {
        self.repository = repository ?? JSONParkingRepository(fileURL: Self.defaultParkingURL)
        Task {
            self.currentParking = await self.repository.loadParking()
        }
    }

    func saveParking(coordinate: CLLocationCoordinate2D, note: String = "", floor: String = "", slot: String = "", photoData: Data? = nil) {
        let parked = ParkedLocation(
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            timestamp: Date(),
            note: note,
            floor: floor,
            slot: slot,
            photoData: photoData
        )
        currentParking = parked
        showsSuggestionPrompt = false
        Task {
            try? await repository.saveParking(parked)
        }
    }

    func clearParking() {
        currentParking = nil
        showsSuggestionPrompt = false
        Task {
            try? await repository.clearParking()
        }
    }

    func updateSpeedAndLocation(speedMPS: Double, coordinate: CLLocationCoordinate2D) {
        if lastSpeed > 4.5 && speedMPS < 0.2 {
            suggestedCoordinate = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            showsSuggestionPrompt = true
        }
        lastSpeed = speedMPS
    }

    private static var defaultParkingURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("KalpanaDrive/parking.json")
    }
}
