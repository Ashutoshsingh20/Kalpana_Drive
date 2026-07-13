import Foundation

public struct ContactMetadata: Codable, Equatable, Sendable {
    public var isFavourite: Bool
    public var lastCalled: Date?

    public init(isFavourite: Bool = false, lastCalled: Date? = nil) {
        self.isFavourite = isFavourite
        self.lastCalled = lastCalled
    }
}

public actor JSONContactsRepository: Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadMetadata() async -> [String: ContactMetadata] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([String: ContactMetadata].self, from: data)
        } catch {
            return [:]
        }
    }

    public func saveMetadata(_ metadata: [String: ContactMetadata]) async throws {
        let data = try encoder.encode(metadata)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
