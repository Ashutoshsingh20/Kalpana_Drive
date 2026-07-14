import XCTest
@testable import KalpanaDriveCore

final class ContactsServiceTests: XCTestCase {
    func testContactInitialsGeneration() {
        let contact = KalpanaContact(
            id: "1",
            displayName: "Ashutosh Singh",
            givenName: "Ashutosh",
            familyName: "Singh",
            organisation: "Kalpana",
            phoneNumbers: [LabeledPhoneNumber(label: "Mobile", number: "+919999999999")]
        )
        XCTAssertEqual(contact.initials, "AS")

        let anonymous = KalpanaContact(
            id: "2",
            displayName: "Google",
            givenName: "",
            familyName: "",
            organisation: "Google",
            phoneNumbers: [LabeledPhoneNumber(label: "Work", number: "111")]
        )
        XCTAssertEqual(anonymous.initials, "?")
    }

    func testContactSorting() {
        let c1 = KalpanaContact(id: "1", displayName: "Zachary", givenName: "Zachary", familyName: "", organisation: "", phoneNumbers: [])
        let c2 = KalpanaContact(id: "2", displayName: "Alice", givenName: "Alice", familyName: "", organisation: "", phoneNumbers: [])
        let c3 = KalpanaContact(id: "3", displayName: "Bob", givenName: "Bob", familyName: "", organisation: "", phoneNumbers: [])

        let list = [c1, c2, c3]
        let sorted = list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        XCTAssertEqual(sorted[0].displayName, "Alice")
        XCTAssertEqual(sorted[1].displayName, "Bob")
        XCTAssertEqual(sorted[2].displayName, "Zachary")
    }

    func testPhoneNumberNormalization() {
        let number = "+91 (999) 999-9999"
        let normalized = number.filter { $0.isNumber || $0 == "+" }
        XCTAssertEqual(normalized, "+919999999999")
    }
}
