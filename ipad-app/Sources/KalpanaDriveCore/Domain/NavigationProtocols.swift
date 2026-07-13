import Foundation

public protocol SavedPlacesRepository: Sendable {
    func loadSavedPlaces() async -> [SavedPlace]
    func savePlace(_ place: SavedPlace) async throws
    func deletePlace(id: UUID) async throws
}

public protocol RecentDestinationsRepository: Sendable {
    func loadRecentDestinations() async -> [Destination]
    func saveRecent(_ destination: Destination) async throws
    func deleteRecent(id: UUID) async throws
    func clearAll() async throws
}

public protocol ParkingRepository: Sendable {
    func loadParking() async -> ParkedLocation?
    func saveParking(_ location: ParkedLocation) async throws
    func clearParking() async throws
}

public protocol TripRepository: Sendable {
    func loadTrips() async -> [TripLog]
    func saveTrip(_ trip: TripLog) async throws
    func deleteTrip(id: UUID) async throws
}

public protocol RoutePreferenceRepository: Sendable {
    func loadRoadPreferences() async -> [PersonalRoadPreference]
    func saveRoadPreference(_ preference: PersonalRoadPreference) async throws
    func deleteRoadPreference(roadName: String) async throws
    func loadAvoidTolls() async -> Bool
    func setAvoidTolls(_ avoid: Bool) async throws
    func loadAvoidHighways() async -> Bool
    func setAvoidHighways(_ avoid: Bool) async throws
}
