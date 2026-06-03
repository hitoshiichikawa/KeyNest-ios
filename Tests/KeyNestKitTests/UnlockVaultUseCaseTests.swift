import XCTest
import CryptoKit
import GRDB
@testable import KeyNestKit

/// Unit tests for `UnlockVaultUseCase` (Phase 2.2 / Req 4.x). Covers the
/// round trip, not-found, password decrypt failure, and the custom-fields
/// fail-open path (password decrypts but custom fields are corrupt).
final class UnlockVaultUseCaseTests: XCTestCase {

    private func makeRepo() throws -> CredentialRepositoryImpl {
        CredentialRepositoryImpl(database: try AppDatabase(DatabaseQueue()))
    }

    private func makeCipher(_ key: SymmetricKey = SymmetricKey(size: .bits256)) -> AesGcmCipher {
        AesGcmCipher(keyProvider: { key })
    }

    func test_unlock_roundTripsPasswordAndCustomFields() async throws {
        let repo = try makeRepo()
        let cipher = makeCipher()
        let codec = EncryptedCustomFieldsCodec(cipher: cipher)
        let save = SaveCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        let unlock = UnlockVaultUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        let fields = [CustomField(fieldKey: "PIN", value: "1234")]

        let id = try await save(NewCredentialInput(serviceIdentifier: "x.com", username: "u", password: Array("secret".utf8), label: "L", customFields: fields))

        let plaintext = try await unlock(id)
        XCTAssertEqual(Data(plaintext.password), Data("secret".utf8))
        XCTAssertEqual(plaintext.customFields, fields)
        XCTAssertEqual(plaintext.serviceIdentifier, "x.com")
        plaintext.close()
    }

    func test_unlock_missing_throwsNotFound() async throws {
        let repo = try makeRepo()
        let cipher = makeCipher()
        let unlock = UnlockVaultUseCase(repository: repo, cipher: cipher, customFieldsCodec: EncryptedCustomFieldsCodec(cipher: cipher))
        await assertThrows(UnlockError.notFound) {
            _ = try await unlock(CredentialId(999))
        }
    }

    func test_unlock_wrongKey_throwsDecryptFailed() async throws {
        let repo = try makeRepo()
        let cipherA = makeCipher()
        let saveA = SaveCredentialUseCase(repository: repo, cipher: cipherA, customFieldsCodec: EncryptedCustomFieldsCodec(cipher: cipherA))
        let id = try await saveA(NewCredentialInput(serviceIdentifier: "x.com", username: "u", password: Array("p".utf8), label: "L"))

        let cipherB = makeCipher()  // different random key
        let unlockB = UnlockVaultUseCase(repository: repo, cipher: cipherB, customFieldsCodec: EncryptedCustomFieldsCodec(cipher: cipherB))
        await assertThrows(UnlockError.decryptFailed) {
            _ = try await unlockB(id)
        }
    }

    func test_unlock_corruptCustomFields_failsOpenToEmpty() async throws {
        let repo = try makeRepo()
        let cipher = makeCipher()
        let codec = EncryptedCustomFieldsCodec(cipher: cipher)

        // Password is validly encrypted; custom fields are deliberate garbage
        // (non-empty, so the codec attempts to decrypt and the AEAD fails).
        let passwordBlob = try cipher.encrypt(Data("pw".utf8))
        let id = try await repo.save(EncryptedCredentialRecord(
            id: CredentialId(0),
            serviceIdentifier: "x.com",
            username: "u",
            label: "L",
            passwordCiphertext: passwordBlob.ciphertext,
            passwordIv: passwordBlob.iv,
            createdAt: 1,
            updatedAt: 1,
            lastUsedAt: nil,
            customFieldsCiphertext: Data(repeating: 0xAB, count: 20),  // >= 16-byte tag, junk
            customFieldsIv: Data(repeating: 0, count: 12)
        ))

        let unlock = UnlockVaultUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        let plaintext = try await unlock(id)

        XCTAssertEqual(Data(plaintext.password), Data("pw".utf8))
        XCTAssertEqual(plaintext.customFields, [], "corrupt custom fields must fail open, not block unlock")
        plaintext.close()
    }
}
