import Foundation

public actor JSONSavedPlacesRepository: SavedPlacesRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadSavedPlaces() async -> [SavedPlace] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([SavedPlace].self, from: data)
        } catch {
            return []
        }
    }

    public func savePlace(_ place: SavedPlace) async throws {
        var list = await loadSavedPlaces()
        if let index = list.firstIndex(where: { $0.id == place.id }) {
            list[index] = place
        } else if let labelIndex = list.firstIndex(where: { $0.label == place.label && place.label != .custom }) {
            list[labelIndex] = place
        } else {
            list.append(place)
        }
        let data = try encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func deletePlace(id: UUID) async throws {
        var list = await loadSavedPlaces()
        list.removeAll(where: { $0.id == id })
        let data = try encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

public actor JSONRecentDestinationsRepository: RecentDestinationsRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadRecentDestinations() async -> [Destination] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([Destination].self, from: data)
        } catch {
            return []
        }
    }

    public func saveRecent(_ destination: Destination) async throws {
        var list = await loadRecentDestinations()
        list.removeAll(where: { $0.id == destination.id })
        list.insert(destination, at: 0) // recent first
        if list.count > 50 {
            list = Array(list.prefix(50))
        }
        let data = try encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func deleteRecent(id: UUID) async throws {
        var list = await loadRecentDestinations()
        list.removeAll(where: { $0.id == id })
        let data = try encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func clearAll() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

public actor JSONParkingRepository: ParkingRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadParking() async -> ParkedLocation? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(ParkedLocation.self, from: data)
        } catch {
            return nil
        }
    }

    public func saveParking(_ location: ParkedLocation) async throws {
        let data = try encoder.encode(location)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func clearParking() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

public actor JSONTripRepository: TripRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadTrips() async -> [TripLog] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([TripLog].self, from: data)
        } catch {
            return []
        }
    }

    public func saveTrip(_ trip: TripLog) async throws {
        var list = await loadTrips()
        list.removeAll(where: { $0.id == trip.id })
        list.append(trip)
        let data = try encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func deleteTrip(id: UUID) async throws {
        var list = await loadTrips()
        list.removeAll(where: { $0.id == id })
        let data = try encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

public actor JSONRoutePreferenceRepository: RoutePreferenceRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct PreferencesContainer: Codable {
        var roadPreferences: [PersonalRoadPreference] = []
        var avoidTolls: Bool = false
        var avoidHighways: Bool = false
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private func loadContainer() async -> PreferencesContainer {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return PreferencesContainer() }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(PreferencesContainer.self, from: data)
        } catch {
            return PreferencesContainer()
        }
    }

    private func saveContainer(_ container: PreferencesContainer) async throws {
        let data = try encoder.encode(container)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func loadRoadPreferences() async -> [PersonalRoadPreference] {
        await loadContainer().roadPreferences
    }

    public func saveRoadPreference(_ preference: PersonalRoadPreference) async throws {
        var container = await loadContainer()
        container.roadPreferences.removeAll(where: { $0.roadName == preference.roadName })
        container.roadPreferences.append(preference)
        try await saveContainer(container)
    }

    public func deleteRoadPreference(roadName: String) async throws {
        var container = await loadContainer()
        container.roadPreferences.removeAll(where: { $0.roadName == roadName })
        try await saveContainer(container)
    }

    public func loadAvoidTolls() async -> Bool {
        await loadContainer().avoidTolls
    }

    public func setAvoidTolls(_ avoid: Bool) async throws {
        var container = await loadContainer()
        container.avoidTolls = avoid
        try await saveContainer(container)
    }

    public func loadAvoidHighways() async -> Bool {
        await loadContainer().avoidHighways
    }

    public func setAvoidHighways(_ avoid: Bool) async throws {
        var container = await loadContainer()
        container.avoidHighways = avoid
        try await saveContainer(container)
    }
}
