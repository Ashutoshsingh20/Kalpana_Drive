import Foundation

public struct LabeledPhoneNumber: Codable, Equatable, Hashable, Sendable {
    public let label: String
    public let number: String

    public init(label: String, number: String) {
        self.label = label
        self.number = number
    }
}

public struct KalpanaContact: Codable, Identifiable, Equatable, Sendable {
    public let id: String // CNContact identifier
    public var displayName: String
    public var givenName: String
    public var familyName: String
    public var organisation: String
    public var phoneNumbers: [LabeledPhoneNumber]
    public var thumbnailImageData: Data?
    public var initials: String
    public var isFavourite: Bool
    public var lastCalled: Date?

    public init(
        id: String,
        displayName: String,
        givenName: String,
        familyName: String,
        organisation: String,
        phoneNumbers: [LabeledPhoneNumber],
        thumbnailImageData: Data? = nil,
        initials: String = "",
        isFavourite: Bool = false,
        lastCalled: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.givenName = givenName
        self.familyName = familyName
        self.organisation = organisation
        self.phoneNumbers = phoneNumbers
        self.thumbnailImageData = thumbnailImageData
        self.initials = initials.isEmpty ? Self.computeInitials(given: givenName, family: familyName) : initials
        self.isFavourite = isFavourite
        self.lastCalled = lastCalled
    }

    private static func computeInitials(given: String, family: String) -> String {
        let first = given.first.map { String($0) } ?? ""
        let second = family.first.map { String($0) } ?? ""
        let initials = (first + second).uppercased()
        return initials.isEmpty ? "?" : initials
    }
}
