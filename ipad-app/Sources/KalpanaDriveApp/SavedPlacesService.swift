import Foundation
import CoreLocation
import KalpanaDriveCore

@MainActor
final class SavedPlacesService: ObservableObject {
    @Published private(set) var savedPlaces: [SavedPlace] = []
    @Published private(set) var recentDestinations: [Destination] = []

    private let placeRepository: SavedPlacesRepository
    private let recentRepository: RecentDestinationsRepository

    var homePlaces: [SavedPlace] { savedPlaces.filter { $0.label == .home } }
    var workPlaces: [SavedPlace] { savedPlaces.filter { $0.label == .work } }
    var collegePlaces: [SavedPlace] { savedPlaces.filter { $0.label == .college } }
    var customPlaces: [SavedPlace] { savedPlaces.filter { $0.label == .custom } }

    init(placeRepository: SavedPlacesRepository? = nil, recentRepository: RecentDestinationsRepository? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.placeRepository = placeRepository ?? JSONSavedPlacesRepository(
            fileURL: appSupport.appendingPathComponent("KalpanaDrive/saved-places.json")
        )
        self.recentRepository = recentRepository ?? JSONRecentDestinationsRepository(
            fileURL: appSupport.appendingPathComponent("KalpanaDrive/recent-destinations.json")
        )
        Task { await self.reload() }
    }

    func reload() async {
        savedPlaces = await placeRepository.loadSavedPlaces()
        recentDestinations = await recentRepository.loadRecentDestinations()
    }

    func savePlace(_ place: SavedPlace) {
        Task {
            try? await placeRepository.savePlace(place)
            await reload()
        }
    }

    func deletePlace(id: UUID) {
        Task {
            try? await placeRepository.deletePlace(id: id)
            await reload()
        }
    }

    func addRecentDestination(_ destination: Destination) {
        Task {
            try? await recentRepository.saveRecent(destination)
            await reload()
        }
    }

    func clearRecentDestinations() {
        Task {
            try? await recentRepository.clearAll()
            await reload()
        }
    }
}
