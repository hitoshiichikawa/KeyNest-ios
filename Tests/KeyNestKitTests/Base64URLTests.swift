import XCTest
@testable import KeyNestKit

/// Unit tests for `Base64URL` (Phase 2.5 support). Locks the URL-safe alphabet
/// and no-padding output used for WebAuthn credential ids.
final class Base64URLTests: XCTestCase {

    func test_encode_usesUrlSafeAlphabetWithoutPadding() {
        // 0xFB 0xFF 0xFE → standard "+//+" → url-safe "-__-", no '=' padding.
        XCTAssertEqual(Base64URL.encode(Data([0xFB, 0xFF, 0xFE])), "-__-")
        // 1 byte → standard "AQ==" → "AQ" (padding stripped).
        XCTAssertEqual(Base64URL.encode(Data([0x01])), "AQ")
    }

    func test_encodeDecode_roundTrips() {
        let data = Data((0..<32).map { UInt8($0) })
        XCTAssertEqual(Base64URL.decode(Base64URL.encode(data)), data)
    }

    func test_decode_invalid_returnsNil() {
        XCTAssertNil(Base64URL.decode("!!!not base64!!!"))
    }
}
