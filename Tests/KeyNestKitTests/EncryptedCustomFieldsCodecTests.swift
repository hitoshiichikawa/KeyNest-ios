import XCTest
import CryptoKit
@testable import KeyNestKit

/// Unit tests for `EncryptedCustomFieldsCodec` (Phase 1 task 1.3 / Req 3.4).
/// Covers the round trip, the empty-list / empty-blob boundaries, the
/// fail-open-on-bad-JSON behaviour, and that a decryption (GCM) failure is NOT
/// swallowed by the fail-open path.
final class EncryptedCustomFieldsCodecTests: XCTestCase {

    private func realCodec() -> EncryptedCustomFieldsCodec {
        let key = SymmetricKey(size: .bits256)
        return EncryptedCustomFieldsCodec(cipher: AesGcmCipher(keyProvider: { key }))
    }

    // MARK: Round trip

    func test_encryptThenDecrypt_roundTripsFields() throws {
        let codec = realCodec()
        let fields = [
            CustomField(fieldKey: "PIN", value: "1234"),
            CustomField(fieldKey: "メモ", value: "秘密の値🔑"),
        ]

        let blob = try codec.encrypt(fields)

        XCTAssertFalse(blob.ciphertext.isEmpty)
        XCTAssertEqual(try codec.decrypt(blob), fields)
    }

    func test_encrypt_emptyList_stillProducesNonEmptyBlob_andDecryptsToEmpty() throws {
        let codec = realCodec()

        let blob = try codec.encrypt([])

        // The codec serialises `[]` first, so even an empty list yields a
        // deterministic IV + ciphertext pair to persist.
        XCTAssertFalse(blob.ciphertext.isEmpty)
        XCTAssertEqual(try codec.decrypt(blob), [])
    }

    // MARK: Boundaries

    func test_decrypt_emptyCiphertext_returnsEmptyList() throws {
        let codec = realCodec()
        let result = try codec.decrypt(EncryptedBlob(iv: Data(), ciphertext: Data()))
        XCTAssertEqual(result, [])
    }

    func test_decrypt_corruptJson_failsOpenToEmptyList() throws {
        // IdentityCipher returns the ciphertext bytes verbatim, so we can feed
        // non-JSON "plaintext" and prove the JSON parse failure is swallowed.
        let codec = EncryptedCustomFieldsCodec(cipher: IdentityCipher())
        let notJson = EncryptedBlob(iv: Data(repeating: 0, count: 12),
                                    ciphertext: Data("this is not json".utf8))

        XCTAssertEqual(try codec.decrypt(notJson), [])
    }

    func test_decrypt_decryptionFailure_isNotSwallowed() throws {
        // A GCM auth-tag failure must propagate (the unlock use case routes it
        // to its decrypt-error surface). Only JSON parse failures are fail-open.
        let codec = EncryptedCustomFieldsCodec(cipher: ThrowingCipher())
        let blob = EncryptedBlob(iv: Data(repeating: 0, count: 12), ciphertext: Data([1, 2, 3]))

        XCTAssertThrowsError(try codec.decrypt(blob)) { error in
            XCTAssertEqual(error as? CryptoError, .decryptionFailed)
        }
    }

    // MARK: Wire format (k / v short keys — byte parity with KeyNest Android)

    func test_encrypt_usesShortKKvVWireFormat() throws {
        let identity = IdentityCipher()
        let codec = EncryptedCustomFieldsCodec(cipher: identity)

        _ = try codec.encrypt([CustomField(fieldKey: "PIN", value: "1234")])

        let captured = try XCTUnwrap(identity.lastEncryptInput)
        let decoded = try JSONSerialization.jsonObject(with: captured) as? [[String: String]]
        XCTAssertEqual(decoded, [["k": "PIN", "v": "1234"]])
    }
}

// MARK: - Test doubles

/// Passes plaintext through unchanged so tests can inspect the JSON the codec
/// produces and feed arbitrary "decrypted" bytes back in.
private final class IdentityCipher: Cipher {
    private(set) var lastEncryptInput: Data?

    func encrypt(_ plaintext: Data) throws -> EncryptedBlob {
        lastEncryptInput = plaintext
        return EncryptedBlob(iv: Data(repeating: 0, count: 12), ciphertext: plaintext)
    }

    func decrypt(_ blob: EncryptedBlob) throws -> Data {
        blob.ciphertext
    }
}

/// Always fails to decrypt (simulates a GCM auth-tag mismatch).
private struct ThrowingCipher: Cipher {
    func encrypt(_ plaintext: Data) throws -> EncryptedBlob {
        EncryptedBlob(iv: Data(), ciphertext: Data())
    }

    func decrypt(_ blob: EncryptedBlob) throws -> Data {
        throw CryptoError.decryptionFailed
    }
}
