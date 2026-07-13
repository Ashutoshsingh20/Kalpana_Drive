import Foundation
import CoreLocation
import KalpanaDriveCore

@MainActor
final class TripRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var trips: [TripLog] = []

    private let repository: TripRepository
    private var currentStartTime: Date?
    private var currentStartCoordinate: Coordinate?
    private var currentRouteTrace: [Coordinate] = []
    private var currentStops: [Coordinate] = []
    private var lastRecordedLocation: CLLocation?
    
    private var totalDistance: Double = 0
    private var maxSpeed: Double = 0
    private var movingDuration: TimeInterval = 0
    private var idleDuration: TimeInterval = 0
    private var lastUpdateTime: Date?

    init(repository: TripRepository? = nil) {
        self.repository = repository ?? JSONTripRepository(fileURL: Self.defaultTripsURL)
        Task {
            self.trips = await self.repository.loadTrips()
        }
    }

    func startTrip(location: CLLocation) {
        guard !isRecording else { return }
        isRecording = true
        currentStartTime = Date()
        currentStartCoordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        currentRouteTrace = [currentStartCoordinate!]
        currentStops = []
        lastRecordedLocation = location
        totalDistance = 0
        maxSpeed = max(0, location.speed)
        movingDuration = 0
        idleDuration = 0
        lastUpdateTime = Date()
    }

    func updateLocation(location: CLLocation) {
        guard isRecording, let startTime = currentStartTime, let lastTime = lastUpdateTime else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        lastUpdateTime = now

        let speed = max(0, location.speed)
        if speed > maxSpeed {
            maxSpeed = speed
        }

        if speed > 1.0 {
            movingDuration += elapsed
        } else {
            idleDuration += elapsed
        }

        if let lastLoc = lastRecordedLocation {
            let dist = location.distance(from: lastLoc)
            if dist > 3 {
                totalDistance += dist
                let coord = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                currentRouteTrace.append(coord)
                lastRecordedLocation = location
            }
        }
    }

    func stopTrip(notes: String = "", isPrivate: Bool = false) {
        guard isRecording, let start = currentStartTime, let startCoord = currentStartCoordinate, let lastLoc = lastRecordedLocation else { return }
        isRecording = false

        let end = Date()
        let duration = end.timeIntervalSince(start)
        let endCoord = Coordinate(latitude: lastLoc.coordinate.latitude, longitude: lastLoc.coordinate.longitude)

        let avgSpeedKPH = duration > 0 ? (totalDistance / duration) * 3.6 : 0
        let maxSpeedKPH = maxSpeed * 3.6

        let calendar = Calendar.current
        var nightTime: TimeInterval = 0
        var checkTime = start
        while checkTime < end {
            let hour = calendar.component(.hour, from: checkTime)
            if hour >= 19 || hour < 6 {
                nightTime += 60
            }
            checkTime = checkTime.addingTimeInterval(60)
        }
        nightTime = min(duration, nightTime)

        let trip = TripLog(
            id: UUID(),
            startTime: start,
            endTime: end,
            startCoordinate: startCoord,
            endCoordinate: endCoord,
            distanceMetres: totalDistance,
            durationSeconds: duration,
            movingDurationSeconds: movingDuration,
            idleDurationSeconds: idleDuration,
            averageSpeedKPH: avgSpeedKPH,
            maxSpeedKPH: maxSpeedKPH,
            routeTrace: currentRouteTrace,
            stops: currentStops,
            nightDrivingDurationSeconds: nightTime,
            notes: notes,
            isPrivate: isPrivate
        )

        trips.append(trip)
        Task {
            try? await repository.saveTrip(trip)
        }
    }

    func deleteTrip(id: UUID) {
        trips.removeAll(where: { $0.id == id })
        Task {
            try? await repository.deleteTrip(id: id)
        }
    }

    func exportCSV(for trip: TripLog) -> String {
        var csv = "Timestamp,Latitude,Longitude\n"
        let formatter = ISO8601DateFormatter()
        let interval = trip.durationSeconds / Double(max(1, trip.routeTrace.count))
        for (index, coord) in trip.routeTrace.enumerated() {
            let time = trip.startTime.addingTimeInterval(Double(index) * interval)
            csv += "\(formatter.string(from: time)),\(coord.latitude),\(coord.longitude)\n"
        }
        return csv
    }

    func exportPDF(for trip: TripLog) -> URL? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("trip-\(trip.id.uuidString).txt")
        let summary = """
        Kalpana Drive Trip Summary
        ID: \(trip.id.uuidString)
        Date: \(trip.startTime.formatted())
        Distance: \(String(format: "%.2f km", trip.distanceMetres / 1000))
        Duration: \(String(format: "%.1f min", trip.durationSeconds / 60))
        Avg Speed: \(String(format: "%.1f km/h", trip.averageSpeedKPH))
        Max Speed: \(String(format: "%.1f km/h", trip.maxSpeedKPH))
        Notes: \(trip.notes)
        """
        do {
            try summary.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    private static var defaultTripsURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("KalpanaDrive/trips.json")
    }
}
