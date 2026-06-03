import Foundation
import CryptoKit

/// AES-256-GCM ciphertext + the 12-byte IV that produced it. Persisted as two
/// separate columns (`*_ciphertext` / `*_iv`), parity with KeyNest `EncryptedBlob`.
public struct EncryptedBlob: Equatable, Sendable {
    public let iv: Data          // 12-byte GCM nonce
    public let ciphertext: Data  // ciphertext ‖ 16-byte tag (Android Cipher layout)

    public init(iv: Data, ciphertext: Data) {
        self.iv = iv
        self.ciphertext = ciphertext
    }
}

public enum CryptoError: Error {
    case decryptionFailed
    case malformedBlob
}

public protocol Cipher {
    func encrypt(_ plaintext: Data) throws -> EncryptedBlob
    func decrypt(_ blob: EncryptedBlob) throws -> Data
}

/// AES-256-GCM authenticated encryption backed by a data-encryption key supplied
/// by `DataKeyProvider`. Direct behavioral port of KeyNest's `AesGcmCipher.kt`:
/// fresh 12-byte IV per call, 128-bit auth tag.
///
/// Layout note: to match the Android `Cipher.doFinal` output (ciphertext with the
/// GCM tag appended), `encrypt` stores `sealedBox.ciphertext + sealedBox.tag` in
/// `ciphertext` and the nonce in `iv`. `decrypt` splits the trailing 16 tag bytes.
public struct AesGcmCipher: Cipher {
    private let keyProvider: () throws -> SymmetricKey
    private static let tagByteCount = 16  // 128-bit tag (GCM_TAG_BITS = 128)

    public init(keyProvider: @escaping () throws -> SymmetricKey) {
        self.keyProvider = keyProvider
    }

    public func encrypt(_ plaintext: Data) throws -> EncryptedBlob {
        let key = try keyProvider()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        let iv = Data(sealed.nonce)
        let ciphertext = sealed.ciphertext + sealed.tag
        return EncryptedBlob(iv: iv, ciphertext: ciphertext)
    }

    public func decrypt(_ blob: EncryptedBlob) throws -> Data {
        guard blob.ciphertext.count >= Self.tagByteCount else { throw CryptoError.malformedBlob }
        let key = try keyProvider()
        let split = blob.ciphertext.count - Self.tagByteCount
        let body = blob.ciphertext.prefix(split)
        let tag = blob.ciphertext.suffix(Self.tagByteCount)
        do {
            let nonce = try AES.GCM.Nonce(data: blob.iv)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
            return try AES.GCM.open(box, using: key)
        } catch {
            // Opaque error: never leak which step failed or any plaintext byte (Req 3.5 / NFR 1.1).
            throw CryptoError.decryptionFailed
        }
    }
}
