import Contacts
import Foundation
import KalpanaDriveCore

@MainActor
final class NativeContactService: ObservableObject {
    @Published private(set) var contacts: [KalpanaContact] = []
    @Published private(set) var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?

    private let store = CNContactStore()
    private let metadataRepository: JSONContactsRepository

    init(metadataRepository: JSONContactsRepository? = nil) {
        let repo = metadataRepository ?? JSONContactsRepository(fileURL: Self.defaultMetadataURL)
        self.metadataRepository = repo
        self.authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            self.authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            if granted {
                await fetchContacts()
            } else {
                lastError = "Access to contacts was denied."
            }
        } catch {
            lastError = "Failed to request access: \(error.localizedDescription)"
        }
    }

    func fetchContacts() async {
        self.authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard self.authorizationStatus == .authorized else {
            contacts = []
            return
        }

        do {
            let metadata = await metadataRepository.loadMetadata()
            let keysToFetch = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]

            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var fetched: [KalpanaContact] = []

            let contactsList = try await Task.detached(priority: .userInitiated) {
                var list: [CNContact] = []
                let store = CNContactStore()
                try store.enumerateContacts(with: request) { contact, _ in
                    list.append(contact)
                }
                return list
            }.value

            for contact in contactsList {
                let displayName = CNContactFormatter.string(from: contact, style: .fullName) ?? 
                    (contact.organizationName.isEmpty ? "Unnamed Contact" : contact.organizationName)

                let phoneNumbers = contact.phoneNumbers.map { labelNum in
                    let label = labelNum.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "Other"
                    let number = labelNum.value.stringValue
                    return LabeledPhoneNumber(label: label, number: number)
                }

                guard !phoneNumbers.isEmpty else { continue }

                let id = contact.identifier
                let meta = metadata[id] ?? ContactMetadata()

                let kContact = KalpanaContact(
                    id: id,
                    displayName: displayName,
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    organisation: contact.organizationName,
                    phoneNumbers: phoneNumbers,
                    thumbnailImageData: contact.thumbnailImageData,
                    isFavourite: meta.isFavourite,
                    lastCalled: meta.lastCalled
                )
                fetched.append(kContact)
            }

            self.contacts = fetched.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            self.lastError = nil
        } catch {
            self.lastError = "Failed to load contacts: \(error.localizedDescription)"
        }
    }

    func toggleFavourite(contactId: String) async {
        var metadata = await metadataRepository.loadMetadata()
        var current = metadata[contactId] ?? ContactMetadata()
        current.isFavourite.toggle()
        metadata[contactId] = current
        try? await metadataRepository.saveMetadata(metadata)

        if let index = contacts.firstIndex(where: { $0.id == contactId }) {
            contacts[index].isFavourite = current.isFavourite
        }
    }

    func recordCall(contactId: String) async {
        var metadata = await metadataRepository.loadMetadata()
        var current = metadata[contactId] ?? ContactMetadata()
        current.lastCalled = Date()
        metadata[contactId] = current
        try? await metadataRepository.saveMetadata(metadata)

        if let index = contacts.firstIndex(where: { $0.id == contactId }) {
            contacts[index].lastCalled = current.lastCalled
        }
    }

    private static var defaultMetadataURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("KalpanaDrive/contacts-metadata.json")
    }
}
