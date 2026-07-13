import Foundation

public enum SavedPlaceLabel: String, Codable, CaseIterable, Sendable {
    case home = "Home"
    case college = "College"
    case work = "Work"
    case custom = "Custom"
}

public struct SavedPlace: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var address: String
    public var coordinate: Coordinate
    public var label: SavedPlaceLabel
    public var customLabelName: String?
    public var linkedContactId: String?

    public init(
        id: UUID = UUID(),
        name: String,
        address: String,
        coordinate: Coordinate,
        label: SavedPlaceLabel,
        customLabelName: String? = nil,
        linkedContactId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.label = label
        self.customLabelName = customLabelName
        self.linkedContactId = linkedContactId
    }
}

public struct ParkedLocation: Codable, Equatable, Sendable {
    public var coordinate: Coordinate
    public var timestamp: Date
    public var note: String
    public var floor: String
    public var slot: String
    public var photoData: Data?

    public init(
        coordinate: Coordinate,
        timestamp: Date = Date(),
        note: String = "",
        floor: String = "",
        slot: String = "",
        photoData: Data? = nil
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.note = note
        self.floor = floor
        self.slot = slot
        self.photoData = photoData
    }
}

public struct TripLog: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var startTime: Date
    public var endTime: Date
    public var startCoordinate: Coordinate
    public var endCoordinate: Coordinate
    public var distanceMetres: Double
    public var durationSeconds: TimeInterval
    public var movingDurationSeconds: TimeInterval
    public var idleDurationSeconds: TimeInterval
    public var averageSpeedKPH: Double
    public var maxSpeedKPH: Double
    public var routeTrace: [Coordinate]
    public var stops: [Coordinate]
    public var nightDrivingDurationSeconds: TimeInterval
    public var notes: String
    public var isPrivate: Bool

    public init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date,
        startCoordinate: Coordinate,
        endCoordinate: Coordinate,
        distanceMetres: Double,
        durationSeconds: TimeInterval,
        movingDurationSeconds: TimeInterval,
        idleDurationSeconds: TimeInterval,
        averageSpeedKPH: Double,
        maxSpeedKPH: Double,
        routeTrace: [Coordinate],
        stops: [Coordinate],
        nightDrivingDurationSeconds: TimeInterval,
        notes: String = "",
        isPrivate: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.startCoordinate = startCoordinate
        self.endCoordinate = endCoordinate
        self.distanceMetres = distanceMetres
        self.durationSeconds = durationSeconds
        self.movingDurationSeconds = movingDurationSeconds
        self.idleDurationSeconds = idleDurationSeconds
        self.averageSpeedKPH = averageSpeedKPH
        self.maxSpeedKPH = maxSpeedKPH
        self.routeTrace = routeTrace
        self.stops = stops
        self.nightDrivingDurationSeconds = nightDrivingDurationSeconds
        self.notes = notes
        self.isPrivate = isPrivate
    }
}

public enum RoadPreferenceType: String, Codable, Sendable {
    case avoid
    case prefer
}

public struct PersonalRoadPreference: Codable, Equatable, Sendable {
    public let roadName: String
    public let preferenceType: RoadPreferenceType
    public let timestamp: Date

    public init(roadName: String, preferenceType: RoadPreferenceType, timestamp: Date = Date()) {
        self.roadName = roadName
        self.preferenceType = preferenceType
        self.timestamp = timestamp
    }
}

public enum TrafficIncidentType: String, Codable, Sendable {
    case accident
    case construction
    case hazard
    case closure
    case other
}

public struct TrafficIncident: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var coordinate: Coordinate
    public var type: TrafficIncidentType
    public var incidentDescription: String
    public var source: String
    public var timestamp: Date
    public var confidence: Double

    public init(
        id: String,
        coordinate: Coordinate,
        type: TrafficIncidentType,
        incidentDescription: String,
        source: String,
        timestamp: Date = Date(),
        confidence: Double = 1.0
    ) {
        self.id = id
        self.coordinate = coordinate
        self.type = type
        self.incidentDescription = incidentDescription
        self.source = source
        self.timestamp = timestamp
        self.confidence = confidence
    }
}
