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
        guard let route = mapRoute, let active = activeRoute, !isPaused, !hasArrived else { return }

        let userCoord = location.coordinate

        let distanceToPolyline = distanceToRoutePolyline(userCoord)
        if distanceToPolyline > 180 {
            if !isOffRoute {
                isOffRoute = true
                speak("You are off route. Recalculating directions.")
                triggerRerouting(from: location)
            }
            return
        } else {
            isOffRoute = false
        }

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
            cancelNavigation()
            return
        }

        let steps = route.steps
        guard currentStepIndex < steps.count else { return }

        let currentStep = steps[currentStepIndex]
        let currentStepLocation = CLLocation(latitude: currentStep.polyline.coordinate.latitude, longitude: currentStep.polyline.coordinate.longitude)
        let distanceToStep = location.distance(from: currentStepLocation)

        if distanceToStep < 45 && currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
            let nextStep = steps[currentStepIndex]
            nextInstruction = nextStep.instructions
            if currentStepIndex + 1 < steps.count {
                nextStreet = steps[currentStepIndex + 1].instructions
            }
            
            if currentStepIndex != lastSpokenStepIndex {
                lastSpokenStepIndex = currentStepIndex
                speak(nextInstruction)
            }
        }

        distanceRemainingMetres = max(0, route.distance - location.distance(from: CLLocation(latitude: route.steps.first?.polyline.coordinate.latitude ?? userCoord.latitude, longitude: route.steps.first?.polyline.coordinate.longitude ?? userCoord.longitude)))
        let totalDistance = route.distance > 0 ? route.distance : 1
        routeProgressPercentage = min(99.9, ((totalDistance - distanceRemainingMetres) / totalDistance) * 100)

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
        
        let firstInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Start driving"
        self.nextInstruction = firstInstruction
        
        self.activeRoute?.distanceRemainingMetres = route.distance
        self.activeRoute?.expectedArrival = self.expectedArrival
        self.activeRoute?.nextInstruction = firstInstruction
        
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
        Task {
            try? await routeRepository.clear()
        }
    }

    func restoreActiveRoute(currentLocation: CLLocation?) async {
        do {
            guard let stored = try await routeRepository.loadActiveRoute() else { return }
            if let currentLocation {
                await recalculateRoute(from: currentLocation, to: stored.destination)
            }
        } catch {}
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
            
            let firstInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Follow route"
            self.nextInstruction = firstInstruction
            
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

    private func distanceToRoutePolyline(_ coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        guard let route = mapRoute else { return .greatestFiniteMagnitude }
        
        var minDistance: CLLocationDistance = .greatestFiniteMagnitude
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        let pointCount = route.polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        
        for coord in coords {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist = userLocation.distance(from: loc)
            if dist < minDistance {
                minDistance = dist
            }
        }
        return minDistance
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
