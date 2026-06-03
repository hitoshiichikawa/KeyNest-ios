import XCTest
@testable import KeyNestKit

/// Locks the WebAuthn byte layout so the iOS port stays byte-identical to
/// KeyNest. These vectors are derived from the CBOR/COSE/WebAuthn specs and the
/// KeyNest implementation; any drift here breaks RP-side verification.
final class WebAuthnByteLayoutTests: XCTestCase {

    // MARK: CBOR primitives

    func test_cbor_byteString32_hasMajorType2LengthHeader() {
        let payload = Data(repeating: 0xAB, count: 32)
        let out = CborWriter().writeByteString(payload).toData()
        // major type 2 (byte string) | length 24 marker → 0x58, then length 0x20 (32)
        XCTAssertEqual(out.prefix(2), Data([0x58, 0x20]))
        XCTAssertEqual(out.count, 34)
    }

    func test_cbor_negativeAndUnsignedInts_matchCoseConstants() {
        XCTAssertEqual(CborWriter().writeUnsignedInt(1).toData(), Data([0x01]))
        XCTAssertEqual(CborWriter().writeUnsignedInt(2).toData(), Data([0x02]))
        XCTAssertEqual(CborWriter().writeNegativeInt(-7).toData(), Data([0x26]))  // ES256
        XCTAssertEqual(CborWriter().writeNegativeInt(-1).toData(), Data([0x20]))  // crv key
        XCTAssertEqual(CborWriter().writeNegativeInt(-2).toData(), Data([0x21]))  // x key
        XCTAssertEqual(CborWriter().writeNegativeInt(-3).toData(), Data([0x22]))  // y key
    }

    func test_cbor_unsignedInt_lengthHeaderBoundaries() {
        XCTAssertEqual(CborWriter().writeUnsignedInt(0).toData(), Data([0x00]))
        XCTAssertEqual(CborWriter().writeUnsignedInt(23).toData(), Data([0x17]))   // inline max
        XCTAssertEqual(CborWriter().writeUnsignedInt(24).toData(), Data([0x18, 0x18]))  // 1-byte marker
    }

    func test_cbor_byteString_lengthHeaderBoundaries() {
        // 24..255 → 0x58 + 1 length byte (registration authData uses this form).
        let mid = CborWriter().writeByteString(Data(repeating: 0, count: 200)).toData()
        XCTAssertEqual(mid.prefix(2), Data([0x58, 0xC8]))  // 200 = 0xC8
        XCTAssertEqual(mid.count, 202)
        // 256..65535 → 0x59 + 2 big-endian length bytes.
        let big = CborWriter().writeByteString(Data(repeating: 0, count: 300)).toData()
        XCTAssertEqual(big.prefix(3), Data([0x59, 0x01, 0x2C]))  // 300 = 0x012C
        XCTAssertEqual(big.count, 303)
    }

    // MARK: COSE_Key (ES256)

    func test_coseKey_es256_exactLayout() throws {
        let x = Data(repeating: 0x11, count: 32)
        let y = Data(repeating: 0x22, count: 32)
        let cose = try CoseKeyEncoder.encodeEs256(x: x, y: y)

        var expected = Data([
            0xA5,             // map(5)
            0x01, 0x02,       // 1: kty = 2 (EC2)
            0x03, 0x26,       // 3: alg = -7 (ES256)
            0x20, 0x01,       // -1: crv = 1 (P-256)
            0x21, 0x58, 0x20, // -2: x = byte string(32)
        ])
        expected.append(x)
        expected.append(Data([0x22, 0x58, 0x20])) // -3: y = byte string(32)
        expected.append(y)

        XCTAssertEqual(cose, expected)
        XCTAssertEqual(cose.count, 77)
    }

    // MARK: Authenticator data

    func test_authData_assertion_is37BytesWithFlags0x05() {
        let rpIdHash = Data(repeating: 0x00, count: 32)
        let authData = AuthenticatorDataBuilder.build(
            rpIdHash: rpIdHash,
            flags: AuthenticatorDataBuilder.flagsAssertion,
            signCount: 1
        )
        XCTAssertEqual(authData.count, 37)
        XCTAssertEqual(authData[32], 0x05)                         // UP | UV
        XCTAssertEqual(authData.suffix(4), Data([0x00, 0x00, 0x00, 0x01])) // signCount BE
    }

    func test_authData_registrationFlags_is0x45() {
        XCTAssertEqual(AuthenticatorDataBuilder.flagsRegistration, 0x45) // UP | UV | AT
    }

    func test_attestedCredentialData_layout() {
        let aaguid = KeynestAaguid.bytes()
        let credentialId = Data(repeating: 0x33, count: 32)
        let cose = Data(repeating: 0x44, count: 77)
        let acd = AuthenticatorDataBuilder.attestedCredentialData(
            aaguid: aaguid,
            credentialId: credentialId,
            publicKeyCose: cose
        )
        XCTAssertEqual(acd.prefix(16), aaguid)
        XCTAssertEqual(acd[16], 0x00)            // credIdLen high byte
        XCTAssertEqual(acd[17], 0x20)            // credIdLen low byte = 32
        XCTAssertEqual(acd.count, 16 + 2 + 32 + 77)
    }

    // MARK: AAGUID

    func test_aaguid_isStableMintedValue() {
        // iOS-minted AAGUID (distinct from Android KeyNest's). Must stay fixed.
        XCTAssertEqual(
            KeynestAaguid.bytes(),
            Data([0xAA, 0xE6, 0x36, 0x3E, 0xFD, 0xB4, 0x4C, 0x71,
                  0xAE, 0xF4, 0x43, 0xC7, 0x9E, 0x5D, 0x59, 0xA3])
        )
        XCTAssertEqual(KeynestAaguid.bytes().count, 16)
    }

    // MARK: Attestation object (fmt = none)

    func test_attestationObject_none_header() {
        let authData = Data(repeating: 0x55, count: 37)
        let obj = AttestationObjectBuilder.buildFormatNone(authenticatorData: authData)
        // map(3) then "fmt":"none" ...
        // 0xA3, 0x63 'f' 'm' 't', 0x64 'n' 'o' 'n' 'e', 0x67 "attStmt", 0xA0, ...
        let head = Data([
            0xA3,
            0x63, 0x66, 0x6D, 0x74,                   // "fmt"
            0x64, 0x6E, 0x6F, 0x6E, 0x65,             // "none"
            0x67, 0x61, 0x74, 0x74, 0x53, 0x74, 0x6D, 0x74, // "attStmt"
            0xA0,                                     // {}
            0x68, 0x61, 0x75, 0x74, 0x68, 0x44, 0x61, 0x74, 0x61, // "authData"
            0x58, 0x25,                               // byte string(37)
        ])
        XCTAssertEqual(obj.prefix(head.count), head)
        XCTAssertEqual(obj.suffix(37), authData)
    }
}
