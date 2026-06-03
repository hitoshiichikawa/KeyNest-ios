import XCTest
import CryptoKit
@testable import KeyNestKit

/// Unit tests for `AesGcmCipher` (Phase 1 task 1.1). Locks the Android-compatible
/// layout (`ciphertext ‖ 16-byte tag`, fresh 12-byte IV per call) and the
/// fail-closed contract on tampering / malformed input.
final class AesGcmCipherTests: XCTestCase {

    private func makeCipher() -> AesGcmCipher {
        let key = SymmetricKey(size: .bits256)
        return AesGcmCipher(keyProvider: { key })
    }

    func test_encryptThenDecrypt_roundTripsPlaintext() throws {
        let cipher = makeCipher()
        let plaintext = Data("hunter2🔑".utf8)

        let blob = try cipher.encrypt(plaintext)

        XCTAssertEqual(blob.iv.count, 12, "GCM nonce must be 12 bytes")
        XCTAssertEqual(try cipher.decrypt(blob), plaintext)
    }

    func test_encrypt_usesAFreshIvEveryCall() throws {
        let cipher = makeCipher()
        let plaintext = Data("same input".utf8)

        let a = try cipher.encrypt(plaintext)
        let b = try cipher.encrypt(plaintext)

        XCTAssertNotEqual(a.iv, b.iv, "each encryption must use a fresh IV")
        XCTAssertNotEqual(a.ciphertext, b.ciphertext, "fresh IV must yield distinct ciphertext")
        // Both still decrypt back to the same plaintext.
        XCTAssertEqual(try cipher.decrypt(a), plaintext)
        XCTAssertEqual(try cipher.decrypt(b), plaintext)
    }

    func test_emptyPlaintext_roundTrips() throws {
        let cipher = makeCipher()
        let blob = try cipher.encrypt(Data())
        // Empty plaintext still produces the 16-byte tag.
        XCTAssertEqual(blob.ciphertext.count, 16)
        XCTAssertEqual(try cipher.decrypt(blob), Data())
    }

    func test_decrypt_tamperedCiphertext_throwsDecryptionFailed() throws {
        let cipher = makeCipher()
        let blob = try cipher.encrypt(Data("secret".utf8))
        var tampered = blob.ciphertext
        tampered[tampered.startIndex] ^= 0xFF

        XCTAssertThrowsError(
            try cipher.decrypt(EncryptedBlob(iv: blob.iv, ciphertext: tampered))
        ) { error in
            // Opaque error only — never leaks which step failed (Req 3.5).
            XCTAssertEqual(error as? CryptoError, .decryptionFailed)
        }
    }

    func test_decrypt_wrongKey_throwsDecryptionFailed() throws {
        let plaintext = Data("secret".utf8)
        let blob = try AesGcmCipher(keyProvider: { SymmetricKey(size: .bits256) }).encrypt(plaintext)

        // A different key must fail the GCM auth tag.
        let otherKey = SymmetricKey(size: .bits256)
        let other = AesGcmCipher(keyProvider: { otherKey })
        XCTAssertThrowsError(try other.decrypt(blob)) { error in
            XCTAssertEqual(error as? CryptoError, .decryptionFailed)
        }
    }

    func test_decrypt_blobShorterThanTag_throwsMalformedBlob() throws {
        let cipher = makeCipher()
        let tooShort = EncryptedBlob(iv: Data(repeating: 0, count: 12),
                                     ciphertext: Data(repeating: 0, count: 4))  // < 16-byte tag
        XCTAssertThrowsError(try cipher.decrypt(tooShort)) { error in
            XCTAssertEqual(error as? CryptoError, .malformedBlob)
        }
    }
}
