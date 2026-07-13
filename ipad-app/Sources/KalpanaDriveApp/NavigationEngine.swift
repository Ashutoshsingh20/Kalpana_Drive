import Foundation
import MapKit
import KalpanaDriveCore
import AVFoundation

@MainActor
final class NavigationEngine: ObservableObject {
    @Published private(set) var activeRoute: RouteSnapshot?
    @Published private(set) var mapRoute: MKRoute?
    @Published private(set) var alternativeRoutes: [MKRoute] = []
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var distanceRemainingMetres: Double = 0
    @Published private(set) var expectedArrival: Date = Date()
    @Published private(set) var nextInstruction: String = ""
    @Published private(set) var currentStreet: String = ""
    @Published private(set) var nextStreet: String = ""
    @Published private(set) var routeProgressPercentage: Double = 0
    @Published private(set) var isOffRoute = false
    @Published private(set) var hasArrived = false
    @Published private(set) var isPaused = false

    private let routeRepository: RouteRepository
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenStepIndex: Int = -1
    private var stepStartDistances: [Double] = []
    private var offRouteSamplesCount = 0

    init(routeRepository: RouteRepository? = nil) {
        let repo = routeRepository ?? JSONRouteRepository(fileURL: Self.defaultRouteURL)
        self.routeRepository = repo
    }

    func startNavigation(with route: MKRoute, target: Destination, alternatives: [MKRoute] = []) {
        self.mapRoute = route
        self.alternativeRoutes = alternatives
        self.currentStepIndex = 0
        self.distanceRemainingMetres = route.distance
        self.expectedArrival = Date().addingTimeInterval(route.expectedTravelTime)
        self.isOffRoute = false
        self.hasArrived = false
        self.isPaused = false
        self.lastSpokenStepIndex = -1
        self.offRouteSamplesCount = 0

        // Parse step start distances along the main polyline
        calculateStepStartDistances(for: route)

        let firstInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Start driving"
        self.nextInstruction = firstInstruction
        self.currentStreet = ""
        self.nextStreet = route.steps.count > 1 ? route.steps[1].instructions : ""
        self.routeProgressPercentage = 0

        self.activeRoute = RouteSnapshot(
            destination: target,
            nextInstruction: firstInstruction,
            distanceRemainingMetres: route.distance,
            expectedArrival: self.expectedArrival,
            isActive: true
        )

        Task {
            if let activeRoute = self.activeRoute {
                try? await routeRepository.save(activeRoute)
            }
        }
        speak("Starting navigation to \(target.name). \(firstInstruction)")
    }

    func updateLocation(_ location: CLLocation) {
        // 1. Reject stale or highly inaccurate locations
        guard abs(location.timestamp.timeIntervalSinceNow) <= 15,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 65 else { return }

        guard let route = mapRoute, let active = activeRoute, !isPaused, !hasArrived else { return }

        let userCoord = location.coordinate

        // 2. Project the current coordinate onto the active route polyline
        let projection = projectLocation(location, onto: route.polyline)
        let distanceToPolyline = projection.distanceToPolyline
        let distanceAlong = projection.distanceAlongPolyline

        // 3. Dynamic off-route threshold detection based on GPS accuracy and speed
        let threshold = max(50.0, location.horizontalAccuracy * 2.0 + (location.speed > 0 ? location.speed * 3.0 : 0.0))
        if distanceToPolyline > threshold {
            offRouteSamplesCount += 1
            if offRouteSamplesCount >= 3 {
                if !isOffRoute {
                    isOffRoute = true
                    speak("You are off route. Recalculating directions.")
                    triggerRerouting(from: location)
                }
            }
            return
        } else {
            offRouteSamplesCount = 0
            isOffRoute = false
        }

        // 4. Destination arrival check
        let destCoord = CLLocationCoordinate2D(
            latitude: active.destination.coordinate.latitude,
            longitude: active.destination.coordinate.longitude
        )
        let distanceToDest = location.distance(from: CLLocation(latitude: destCoord.latitude, longitude: destCoord.longitude))
        if distanceToDest < 35 {
            hasArrived = true
            distanceRemainingMetres = 0
            routeProgressPercentage = 100
            nextInstruction = "You have arrived at your destination."
            speak("You have arrived at your destination.")
            // Keep arrival state, do not clear/cancel automatically
            return
        }

        // 5. Match the projected position to the current MKRouteStep and advance
        var matchedIndex = 0
        for (idx, startDist) in stepStartDistances.enumerated() {
            if distanceAlong >= startDist {
                matchedIndex = idx
            } else {
                break
            }
        }

        let steps = route.steps
        guard matchedIndex < steps.count else { return }

        // Proximity check for step end to advance early
        var activeStepIndex = matchedIndex
        if activeStepIndex < steps.count - 1 {
            let nextStepStartDist = stepStartDistances[activeStepIndex + 1]
            let distanceToNextManeuver = max(0, nextStepStartDist - distanceAlong)
            // If user is within maneuver proximity (45 meters), advance index early
            if distanceToNextManeuver < 45 {
                activeStepIndex += 1
            }
        }

        currentStepIndex = activeStepIndex
        let currentStep = steps[currentStepIndex]
        nextInstruction = currentStep.instructions
        currentStreet = extractStreet(from: currentStep.instructions)
        if currentStepIndex + 1 < steps.count {
            nextStreet = steps[currentStepIndex + 1].instructions
        }

        if currentStepIndex != lastSpokenStepIndex {
            lastSpokenStepIndex = currentStepIndex
            speak(nextInstruction)
        }

        // 6. Calculate accurate remaining distance
        distanceRemainingMetres = max(0, route.distance - distanceAlong)
        let totalDistance = route.distance > 0 ? route.distance : 1.0
        routeProgressPercentage = min(99.9, (distanceAlong / totalDistance) * 100)

        // 7. Update ETA and active snapshot
        let ratio = distanceRemainingMetres / totalDistance
        let remainingTime = route.expectedTravelTime * ratio
        expectedArrival = Date().addingTimeInterval(remainingTime)

        self.activeRoute?.distanceRemainingMetres = distanceRemainingMetres
        self.activeRoute?.expectedArrival = expectedArrival
        self.activeRoute?.nextInstruction = nextInstruction
    }

    func selectAlternativeRoute(_ route: MKRoute) {
        self.mapRoute = route
        self.currentStepIndex = 0
        self.distanceRemainingMetres = route.distance
        self.expectedArrival = Date().addingTimeInterval(route.expectedTravelTime)
        self.isOffRoute = false
        self.hasArrived = false
        self.offRouteSamplesCount = 0

        calculateStepStartDistances(for: route)

        let firstInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Follow route"
        self.nextInstruction = firstInstruction
        self.currentStreet = ""
        self.nextStreet = route.steps.count > 1 ? route.steps[1].instructions : ""
        self.routeProgressPercentage = 0

        self.activeRoute?.distanceRemainingMetres = route.distance
        self.activeRoute?.expectedArrival = self.expectedArrival
        self.activeRoute?.nextInstruction = firstInstruction

        Task {
            if let activeRoute = self.activeRoute {
                try? await routeRepository.save(activeRoute)
            }
        }
        speak("Rerouting. \(firstInstruction)")
    }

    func pauseNavigation() {
        isPaused = true
    }

    func resumeNavigation(from location: CLLocation) {
        isPaused = false
        triggerRerouting(from: location)
    }

    func cancelNavigation() {
        mapRoute = nil
        alternativeRoutes = []
        activeRoute = nil
        hasArrived = false
        isOffRoute = false
        offRouteSamplesCount = 0
        stepStartDistances = []
        Task {
            try? await routeRepository.clear()
        }
    }

    func restoreActiveRoute(currentLocation: CLLocation?) async {
        do {
            guard let stored = try await routeRepository.loadActiveRoute() else { return }
            self.activeRoute = stored
            self.distanceRemainingMetres = stored.distanceRemainingMetres
            self.expectedArrival = stored.expectedArrival
            self.nextInstruction = stored.nextInstruction
            if let currentLocation {
                await recalculateRoute(from: currentLocation, to: stored.destination)
            }
        } catch {}
    }

    private func calculateStepStartDistances(for route: MKRoute) {
        var stepStarts: [Double] = []
        let mainPolyline = route.polyline
        let mainPointCount = mainPolyline.pointCount
        var mainCoords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: mainPointCount)
        mainPolyline.getCoordinates(&mainCoords, range: NSRange(location: 0, length: mainPointCount))
        let mainPoints = mainCoords.map { MKMapPoint($0) }

        for step in route.steps {
            let stepStartPoint = MKMapPoint(step.polyline.coordinate)
            var minD: Double = .greatestFiniteMagnitude
            var closestIdx = 0
            for (idx, pt) in mainPoints.enumerated() {
                let d = pt.distance(to: stepStartPoint)
                if d < minD {
                    minD = d
                    closestIdx = idx
                }
            }
            var dist = 0.0
            for idx in 0..<closestIdx {
                dist += mainPoints[idx].distance(to: mainPoints[idx + 1])
            }
            stepStarts.append(dist)
        }
        self.stepStartDistances = stepStarts
    }

    private func projectLocation(_ location: CLLocation, onto polyline: MKPolyline) -> (projectedCoordinate: CLLocationCoordinate2D, distanceToPolyline: Double, distanceAlongPolyline: Double) {
        let userPoint = MKMapPoint(location.coordinate)
        let pointCount = polyline.pointCount
        guard pointCount > 0 else {
            return (location.coordinate, 0, 0)
        }
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        let points = coords.map { MKMapPoint($0) }

        var closestPoint = points[0]
        var minDistance: Double = .greatestFiniteMagnitude
        var closestSegmentIndex = 0
        var closestT: Double = 0

        var accumulatedDistances: [Double] = [0]
        for idx in 0..<(pointCount - 1) {
            let pA = points[idx]
            let pB = points[idx + 1]
            let segLength = pA.distance(to: pB)
            accumulatedDistances.append(accumulatedDistances.last! + segLength)
        }

        for idx in 0..<(pointCount - 1) {
            let pA = points[idx]
            let pB = points[idx + 1]
            let ab = MKMapPoint(x: pB.x - pA.x, y: pB.y - pA.y)
            let au = MKMapPoint(x: userPoint.x - pA.x, y: userPoint.y - pA.y)

            let ab2 = ab.x * ab.x + ab.y * ab.y
            var t = ab2 > 0 ? (au.x * ab.x + au.y * ab.y) / ab2 : 0
            t = max(0, min(1, t))

            let projected = MKMapPoint(x: pA.x + t * ab.x, y: pA.y + t * ab.y)
            let dist = userPoint.distance(to: projected)

            if dist < minDistance {
                minDistance = dist
                closestPoint = projected
                closestSegmentIndex = idx
                closestT = t
            }
        }

        let distanceAlong = accumulatedDistances[closestSegmentIndex] + (closestT * points[closestSegmentIndex].distance(to: points[closestSegmentIndex + 1]))
        return (closestPoint.coordinate, minDistance, distanceAlong)
    }

    private func extractStreet(from instructions: String) -> String {
        let patterns = ["onto ", "toward ", "towards "]
        for pattern in patterns {
            if let range = instructions.range(of: pattern, options: .caseInsensitive) {
                return String(instructions[range.upperBound...])
            }
        }
        return instructions
    }

    private func triggerRerouting(from location: CLLocation) {
        guard let active = activeRoute else { return }
        Task {
            await recalculateRoute(from: location, to: active.destination)
        }
    }

    private func recalculateRoute(from location: CLLocation, to destination: Destination) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(
            placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(
                    latitude: destination.coordinate.latitude,
                    longitude: destination.coordinate.longitude
                )
            )
        )
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else { return }
            self.mapRoute = route
            self.alternativeRoutes = response.routes.filter { $0 !== route }
            self.currentStepIndex = 0
            self.distanceRemainingMetres = route.distance
            self.expectedArrival = Date().addingTimeInterval(route.expectedTravelTime)
            self.isOffRoute = false
            self.offRouteSamplesCount = 0

            calculateStepStartDistances(for: route)

            let firstInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Follow route"
            self.nextInstruction = firstInstruction
            self.currentStreet = ""
            self.nextStreet = route.steps.count > 1 ? route.steps[1].instructions : ""
            self.routeProgressPercentage = 0

            self.activeRoute = RouteSnapshot(
                destination: destination,
                nextInstruction: firstInstruction,
                distanceRemainingMetres: route.distance,
                expectedArrival: self.expectedArrival,
                isActive: true
            )
            try? await routeRepository.save(self.activeRoute!)
        } catch {}
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
        utterance.rate = 0.50
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        speechSynthesizer.speak(utterance)
    }

    private static var defaultRouteURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("KalpanaDrive/active-route.json")
    }
}
