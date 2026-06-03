import XCTest
import CryptoKit
import GRDB
@testable import KeyNestKit

/// Unit tests for `PasskeyCreator` (Phase 2.5 / Req 6.1, 6.2). Verifies the
/// WebAuthn registration bytes are composed correctly (AAGUID, flags, COSE
/// placement, attestation-object framing) and that the produced private key
/// round-trips through the DEK-encrypted repository.
final class PasskeyCreatorTests: XCTestCase {

    // fmt="none" attestation object header (map(3) "fmt":"none" "attStmt":{} "authData":).
    private let attestationHeader: [UInt8] = [
        0xA3,
        0x63, 0x66, 0x6D, 0x74,                          // "fmt"
        0x64, 0x6E, 0x6F, 0x6E, 0x65,                    // "none"
        0x67, 0x61, 0x74, 0x74, 0x53, 0x74, 0x6D, 0x74,  // "attStmt"
        0xA0,                                            // {}
        0x68, 0x61, 0x75, 0x74, 0x68, 0x44, 0x61, 0x74, 0x61,  // "authData"
    ]

    func test_create_composesRegistrationBytes() throws {
        let key = P256.Signing.PrivateKey()
        let credentialIdBytes = Data((0..<32).map { UInt8($0) })
        let creator = PasskeyCreator(
            makeCredentialIdBytes: { credentialIdBytes },
            makePrivateKey: { key },
            now: { 1234 }
        )

        let result = try creator.create(PasskeyCreateInput(
            rpId: "example.com", rpDisplayName: "Example", userHandle: Data([0xAA]),
            userName: "alice", userDisplayName: "Alice", isDiscoverable: true
        ))

        // credentialId
        XCTAssertEqual(result.credentialIdBytes, credentialIdBytes)
        XCTAssertEqual(result.credentialId, Base64URL.encode(credentialIdBytes))

        // COSE (consistent with the byte-locked encoder; exact layout is fixed
        // independently in WebAuthnByteLayoutTests).
        let expectedCose = try CoseKeyEncoder.encodeEs256(rawXY: key.publicKey.rawRepresentation)
        XCTAssertEqual(result.publicKeyCose, expectedCose)
        XCTAssertEqual(result.publicKeyCose.count, 77)

        // authenticatorData: rpIdHash(32) | 0x45 | signCount(4) | AAGUID(16) |
        // credIdLen(2) | credentialId(32) | COSE(77)  = 164 bytes.
        let ad = [UInt8](result.authenticatorData)
        XCTAssertEqual(ad.count, 164)
        XCTAssertEqual(Data(ad[0..<32]), Data(SHA256.hash(data: Data("example.com".utf8))))
        XCTAssertEqual(ad[32], 0x45)                                   // UP|UV|AT
        XCTAssertEqual(Array(ad[33..<37]), [0x00, 0x00, 0x00, 0x00])   // signCount 0
        XCTAssertEqual(Data(ad[37..<53]), KeynestAaguid.bytes())       // AAGUID
        XCTAssertEqual(Array(ad[53..<55]), [0x00, 0x20])               // credIdLen = 32
        XCTAssertEqual(Data(ad[55..<87]), credentialIdBytes)
        XCTAssertEqual(Data(ad[87..<164]), expectedCose)

        // attestationObject = header(28) | 0x58 0xA4 (byte string, len 164) | authData(164).
        let ao = [UInt8](result.attestationObject)
        XCTAssertEqual(ao.count, attestationHeader.count + 2 + 164)
        XCTAssertEqual(Array(ao.prefix(attestationHeader.count)), attestationHeader)
        XCTAssertEqual(Array(ao[28..<30]), [0x58, 0xA4])
        XCTAssertEqual(Array(ao.suffix(164)), ad)

        // savePasskeyRequest carries the raw private key + metadata.
        XCTAssertEqual(result.savePasskeyRequest.credentialId, result.credentialId)
        XCTAssertEqual(result.savePasskeyRequest.privateKey, key.rawRepresentation)
        XCTAssertEqual(result.savePasskeyRequest.signCount, 0)
        XCTAssertEqual(result.savePasskeyRequest.createdAt, 1234)
        XCTAssertEqual(result.savePasskeyRequest.isDiscoverable, true)
        XCTAssertEqual(result.savePasskeyRequest.displayName, "Alice")  // userDisplayName ?? userName
    }

    func test_create_storedPrivateKeyRoundTripsThroughDek() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let key = SymmetricKey(size: .bits256)
        let repo = PasskeyRepositoryImpl(database: database, cipher: AesGcmCipher(keyProvider: { key }))
        let creator = PasskeyCreator()

        let result = try creator.create(PasskeyCreateInput(
            rpId: "example.com", rpDisplayName: nil, userHandle: Data([1]),
            userName: "u", userDisplayName: nil, isDiscoverable: true
        ))
        try await repo.save(result.savePasskeyRequest)

        let loaded = try await repo.loadPrivateKey(credentialId: result.credentialId)
        XCTAssertEqual(loaded, result.savePasskeyRequest.privateKey, "DEK encrypt/decrypt must round-trip the key")
        let unwrapped = try XCTUnwrap(loaded)
        _ = try P256.Signing.PrivateKey(rawRepresentation: unwrapped)  // must reconstruct a valid key
    }
}
