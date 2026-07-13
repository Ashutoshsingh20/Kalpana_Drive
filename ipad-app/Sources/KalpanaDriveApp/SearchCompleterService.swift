import Foundation
import MapKit
import KalpanaDriveCore

@MainActor
final class SearchCompleterService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    
    func updateQuery(_ query: String, coordinate: CLLocationCoordinate2D?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        
        if let coordinate {
            completer.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }
        completer.queryText = trimmed
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
