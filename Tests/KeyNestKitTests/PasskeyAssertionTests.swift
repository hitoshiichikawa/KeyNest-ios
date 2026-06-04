import XCTest
import CryptoKit
@testable import KeyNestKit

/// Unit tests for `PasskeyAssertion` (Phase 2.5 / Req 6.3). Verifies the 37-byte
/// authenticatorData layout (flags 0x1D) and that the DER signature validates
/// against the registered public key over `authData ‖ clientDataHash`. ECDSA is
/// non-deterministic, so signature *validity* is asserted, not exact bytes.
final class PasskeyAssertionTests: XCTestCase {

    func test_sign_buildsAuthData37BytesAndValidSignature() throws {
        let key = P256.Signing.PrivateKey()
        let clientDataHash = Data(SHA256.hash(data: Data("{\"type\":\"webauthn.get\"}".utf8)))

        let result = try PasskeyAssertion.sign(PasskeyAssertionInput(
            rpId: "example.com",
            clientDataHash: clientDataHash,
            signCount: 42,
            privateKey: key.rawRepresentation
        ))

        let ad = [UInt8](result.authenticatorData)
        XCTAssertEqual(ad.count, 37)
        XCTAssertEqual(Data(ad[0..<32]), Data(SHA256.hash(data: Data("example.com".utf8))))
        XCTAssertEqual(ad[32], 0x1D)                                   // UP|UV|BE|BS
        XCTAssertEqual(Array(ad[33..<37]), [0x00, 0x00, 0x00, 0x2A])   // signCount 42 BE

        let signature = try P256.Signing.ECDSASignature(derRepresentation: result.signature)
        XCTAssertTrue(
            key.publicKey.isValidSignature(signature, for: result.authenticatorData + clientDataHash),
            "signature must verify over authData ‖ clientDataHash"
        )
    }

    func test_endToEnd_createThenAssertion_verifiesWithRegisteredKey() throws {
        let created = try PasskeyCreator().create(PasskeyCreateInput(
            rpId: "example.com", rpDisplayName: nil, userHandle: Data([1]),
            userName: "u", userDisplayName: nil, isDiscoverable: true
        ))
        let clientDataHash = Data(SHA256.hash(data: Data("client-data".utf8)))

        let assertion = try PasskeyAssertion.sign(PasskeyAssertionInput(
            rpId: "example.com",
            clientDataHash: clientDataHash,
            signCount: 1,
            privateKey: created.savePasskeyRequest.privateKey
        ))

        let registeredKey = try P256.Signing.PrivateKey(rawRepresentation: created.savePasskeyRequest.privateKey)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: assertion.signature)
        XCTAssertTrue(
            registeredKey.publicKey.isValidSignature(signature, for: assertion.authenticatorData + clientDataHash)
        )
    }

    func test_sign_signCountOutOfRange_throwsEncoding() {
        let key = P256.Signing.PrivateKey()
        let input = PasskeyAssertionInput(
            rpId: "x", clientDataHash: Data(repeating: 0, count: 32),
            signCount: 0x1_0000_0000, privateKey: key.rawRepresentation  // > unsigned 32-bit
        )
        XCTAssertThrowsError(try PasskeyAssertion.sign(input)) {
            XCTAssertEqual($0 as? PasskeyAssertionError, .encoding)
        }
    }

    func test_sign_invalidPrivateKey_throwsInvalidPrivateKey() {
        let input = PasskeyAssertionInput(
            rpId: "x", clientDataHash: Data(repeating: 0, count: 32),
            signCount: 0, privateKey: Data([1, 2, 3])  // not a 32-byte P-256 scalar
        )
        XCTAssertThrowsError(try PasskeyAssertion.sign(input)) {
            XCTAssertEqual($0 as? PasskeyAssertionError, .invalidPrivateKey)
        }
    }
}
