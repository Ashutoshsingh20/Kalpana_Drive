import Foundation

public actor JSONRouteRepository: RouteRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ route: RouteSnapshot) async throws {
        let data = try encoder.encode(route)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func loadActiveRoute() async throws -> RouteSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let route = try decoder.decode(RouteSnapshot.self, from: Data(contentsOf: fileURL))
        return route.isActive ? route : nil
    }

    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
