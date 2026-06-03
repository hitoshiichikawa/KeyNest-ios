import XCTest
@testable import KeyNestKit

final class TextToInsertOptionsTests: XCTestCase {

    private func makePlaintext(
        username: String,
        password: String,
        customFields: [CustomField] = []
    ) -> PlaintextCredential {
        PlaintextCredential(
            id: CredentialId(1),
            serviceIdentifier: "example.com",
            username: username,
            label: "Label",
            password: Array(password.utf8),
            customFields: customFields
        )
    }

    func test_orderIsUsernameThenPasswordThenCustomFields() {
        let plaintext = makePlaintext(
            username: "alice",
            password: "hunter2",
            customFields: [
                CustomField(fieldKey: "company_id", value: "ACME-42"),
                CustomField(fieldKey: "pin", value: "1234"),
            ]
        )
        defer { plaintext.close() }

        let options = TextToInsertOptions.options(from: plaintext)
        XCTAssertEqual(options.map(\.id), ["username", "password", "custom:company_id", "custom:pin"])
        XCTAssertEqual(options.map(\.displayName), ["Username", "Password", "company_id", "pin"])
        XCTAssertEqual(options.map(\.value), ["alice", "hunter2", "ACME-42", "1234"])
    }

    func test_skipsBlankFields() {
        let plaintext = makePlaintext(
            username: "   ",
            password: "",
            customFields: [
                CustomField(fieldKey: "company_id", value: ""),
                CustomField(fieldKey: "pin", value: "1234"),
            ]
        )
        defer { plaintext.close() }

        let options = TextToInsertOptions.options(from: plaintext)
        XCTAssertEqual(options.map(\.id), ["custom:pin"])
    }

    func test_trimsUsername_butKeepsPasswordRaw() {
        let plaintext = makePlaintext(username: "  alice  ", password: "  he llo  ")
        defer { plaintext.close() }

        let options = TextToInsertOptions.options(from: plaintext)
        XCTAssertEqual(options[0].value, "alice", "username is trimmed")
        XCTAssertEqual(options[1].value, "  he llo  ", "password is preserved verbatim — leading/trailing space may be intentional")
    }

    func test_kindFlagsSensitivityCorrectly() {
        let plaintext = makePlaintext(
            username: "alice",
            password: "hunter2",
            customFields: [CustomField(fieldKey: "company_id", value: "ACME-42")]
        )
        defer { plaintext.close() }

        let options = TextToInsertOptions.options(from: plaintext)
        XCTAssertEqual(options.map(\.isSensitive), [false, true, true])
    }

    func test_fallbackLabel_whenCustomFieldKeyIsBlank() {
        let plaintext = makePlaintext(
            username: "u",
            password: "p",
            customFields: [CustomField(fieldKey: "  ", value: "x")]
        )
        defer { plaintext.close() }

        let options = TextToInsertOptions.options(from: plaintext)
        XCTAssertEqual(options.last?.displayName, "Custom")
    }
}
