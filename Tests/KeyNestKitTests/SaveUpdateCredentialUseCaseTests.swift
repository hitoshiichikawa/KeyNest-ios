import XCTest
import CryptoKit
import GRDB
@testable import KeyNestKit

/// Unit tests for `SaveCredentialUseCase` / `UpdateCredentialUseCase`
/// (Phase 2.2). The headline case is the password-preservation boundary: a
/// metadata-only update must NOT re-encrypt the password.
final class SaveUpdateCredentialUseCaseTests: XCTestCase {

    private func makeContext() throws -> (CredentialRepositoryImpl, AesGcmCipher, EncryptedCustomFieldsCodec) {
        let key = SymmetricKey(size: .bits256)
        let cipher = AesGcmCipher(keyProvider: { key })
        let repo = CredentialRepositoryImpl(database: try AppDatabase(DatabaseQueue()))
        return (repo, cipher, EncryptedCustomFieldsCodec(cipher: cipher))
    }

    // MARK: Save

    func test_save_persistsCredential() async throws {
        let (repo, cipher, codec) = try makeContext()
        let save = SaveCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec, now: { 1000 })

        let id = try await save(NewCredentialInput(
            serviceIdentifier: "example.com",
            username: "alice",
            password: Array("hunter2".utf8),
            label: "Example"
        ))

        let stored = try await repo.findById(id)
        XCTAssertEqual(stored?.serviceIdentifier, "example.com")
        XCTAssertEqual(stored?.label, "Example")
        XCTAssertEqual(stored?.createdAt, 1000)
        XCTAssertEqual(stored?.updatedAt, 1000)
        XCTAssertFalse(stored?.passwordCiphertext.isEmpty ?? true)
        // Custom fields are always encrypted ([] → non-empty blob).
        XCTAssertFalse(stored?.customFieldsCiphertext.isEmpty ?? true)
    }

    func test_save_blankServiceIdentifier_throws() async throws {
        let (repo, cipher, codec) = try makeContext()
        let save = SaveCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        await assertThrows(SaveCredentialError.serviceIdentifierBlank) {
            _ = try await save(NewCredentialInput(serviceIdentifier: "  ", username: "u", password: Array("p".utf8), label: "L"))
        }
    }

    func test_save_emptyPassword_throws() async throws {
        let (repo, cipher, codec) = try makeContext()
        let save = SaveCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        await assertThrows(SaveCredentialError.passwordBlank) {
            _ = try await save(NewCredentialInput(serviceIdentifier: "x.com", username: "u", password: [], label: "L"))
        }
    }

    // MARK: Update — password preservation boundary

    func test_update_withNilPassword_preservesCiphertext() async throws {
        let (repo, cipher, codec) = try makeContext()
        let save = SaveCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec, now: { 1000 })
        let update = UpdateCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec, now: { 2000 })

        let id = try await save(NewCredentialInput(serviceIdentifier: "example.com", username: "alice", password: Array("pw".utf8), label: "Old"))
        let before = try await repo.findById(id)!

        try await update(UpdateCredentialInput(id: id, serviceIdentifier: "example.com", username: "alice", label: "New", newPassword: nil, customFields: nil))

        let after = try await repo.findById(id)!
        XCTAssertEqual(after.label, "New")
        XCTAssertEqual(after.updatedAt, 2000)
        XCTAssertEqual(after.createdAt, before.createdAt)
        XCTAssertEqual(after.passwordCiphertext, before.passwordCiphertext, "metadata-only edit must not re-encrypt")
        XCTAssertEqual(after.passwordIv, before.passwordIv)
    }

    func test_update_withNewPassword_reEncrypts() async throws {
        let (repo, cipher, codec) = try makeContext()
        let save = SaveCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        let update = UpdateCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        let unlock = UnlockVaultUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)

        let id = try await save(NewCredentialInput(serviceIdentifier: "x.com", username: "u", password: Array("old".utf8), label: "L"))
        let before = try await repo.findById(id)!

        try await update(UpdateCredentialInput(id: id, serviceIdentifier: "x.com", username: "u", label: "L", newPassword: Array("new".utf8), customFields: nil))

        let after = try await repo.findById(id)!
        XCTAssertNotEqual(after.passwordCiphertext, before.passwordCiphertext)
        let plaintext = try await unlock(id)
        XCTAssertEqual(Data(plaintext.password), Data("new".utf8))
        plaintext.close()
    }

    func test_update_preservesLastUsedAt() async throws {
        // iOS divergence from KeyNest Android: editing keeps lastUsedAt.
        let (repo, cipher, codec) = try makeContext()
        let save = SaveCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        let update = UpdateCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)

        let id = try await save(NewCredentialInput(serviceIdentifier: "x.com", username: "u", password: Array("p".utf8), label: "L"))
        try await repo.markUsed(id, timestamp: 555)

        try await update(UpdateCredentialInput(id: id, serviceIdentifier: "x.com", username: "u", label: "L2", newPassword: nil, customFields: nil))

        let after = try await repo.findById(id)!
        XCTAssertEqual(after.lastUsedAt, 555)
    }

    func test_update_missing_throwsNotFound() async throws {
        let (repo, cipher, codec) = try makeContext()
        let update = UpdateCredentialUseCase(repository: repo, cipher: cipher, customFieldsCodec: codec)
        await assertThrows(UpdateCredentialError.notFound) {
            try await update(UpdateCredentialInput(id: CredentialId(999), serviceIdentifier: "x.com", username: "u", label: "L"))
        }
    }
}

/// Asserts the async expression throws a specific equatable error.
func assertThrows<E: Error & Equatable>(
    _ expected: E,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("expected \(expected) to be thrown", file: file, line: line)
    } catch let error as E {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("expected \(expected) but got \(error)", file: file, line: line)
    }
}
