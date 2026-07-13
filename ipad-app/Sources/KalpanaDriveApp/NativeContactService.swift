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

        let metadata = await metadataRepository.loadMetadata()

        // ALL CNContact work (fetch + map) stays inside the detached task
        // so no CNContact (non-Sendable) object ever crosses an actor boundary.
        let result: Result<[KalpanaContact], Error> = await Task.detached(priority: .userInitiated) {
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var fetched: [KalpanaContact] = []
            do {
                try CNContactStore().enumerateContacts(with: request) { contact, _ in
                    let displayName = CNContactFormatter.string(from: contact, style: .fullName)
                        ?? (contact.organizationName.isEmpty ? "Unnamed Contact" : contact.organizationName)

                    let phoneNumbers = contact.phoneNumbers.map { labelNum -> LabeledPhoneNumber in
                        let label = labelNum.label.map {
                            CNLabeledValue<NSString>.localizedString(forLabel: $0)
                        } ?? "Other"
                        return LabeledPhoneNumber(label: label, number: labelNum.value.stringValue)
                    }

                    guard !phoneNumbers.isEmpty else { return }

                    let id = contact.identifier
                    let meta = metadata[id] ?? ContactMetadata()

                    fetched.append(KalpanaContact(
                        id: id,
                        displayName: displayName,
                        givenName: contact.givenName,
                        familyName: contact.familyName,
                        organisation: contact.organizationName,
                        phoneNumbers: phoneNumbers,
                        thumbnailImageData: contact.thumbnailImageData,
                        isFavourite: meta.isFavourite,
                        lastCalled: meta.lastCalled
                    ))
                }
                return .success(fetched.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                })
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let list):
            self.contacts = list
            self.lastError = nil
        case .failure(let error):
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
