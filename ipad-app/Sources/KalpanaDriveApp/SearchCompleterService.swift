import Foundation
import MapKit
import KalpanaDriveCore

@MainActor
final class SearchCompleterService: NSObject, ObservableObject {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var delegate: CompleterDelegate?

    override init() {
        super.init()
        let d = CompleterDelegate { [weak self] results in
            Task { @MainActor in
                self?.suggestions = results
            }
        }
        self.delegate = d
        completer.delegate = d
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String, coordinate: CLLocationCoordinate2D?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            // Clear completer query off main thread to avoid isolation issues
            let c = completer
            DispatchQueue.main.async { c.queryFragment = "" }
            return
        }

        if let coordinate {
            completer.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }
        completer.queryFragment = trimmed
    }

    // Separate NSObject delegate to avoid main-actor crossing issue
    private final class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
        var onUpdate: ([MKLocalSearchCompletion]) -> Void

        init(onUpdate: @escaping ([MKLocalSearchCompletion]) -> Void) {
            self.onUpdate = onUpdate
        }

        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            onUpdate(completer.results)
        }

        func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
            onUpdate([])
        }
    }
}
