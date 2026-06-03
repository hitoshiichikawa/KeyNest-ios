import XCTest
import CryptoKit
import GRDB
@testable import KeyNestKit

/// Unit tests for `ClearVaultUseCase` (Phase 2.2 / Req 7.4): clears credentials,
/// passkeys, and the data-encryption key material.
final class ClearVaultUseCaseTests: XCTestCase {

    func test_clear_removesCredentialsPasskeysAndKeyMaterial() async throws {
        let database = try AppDatabase(DatabaseQueue())
        let credentialRepo = CredentialRepositoryImpl(database: database)
        let key = SymmetricKey(size: .bits256)
        let cipher = AesGcmCipher(keyProvider: { key })
        let passkeyRepo = PasskeyRepositoryImpl(database: database, cipher: cipher)
        let spyKeyProvider = SpyDataKeyProvider()

        _ = try await credentialRepo.save(EncryptedCredentialRecord(
            id: CredentialId(0), serviceIdentifier: "x.com", username: "u", label: "L",
            passwordCiphertext: Data([1, 2, 3]), passwordIv: Data(repeating: 0, count: 12),
            createdAt: 1, updatedAt: 1
        ))
        try await passkeyRepo.save(SavePasskeyRequest(
            credentialId: "c1", rpId: "x.com", rpDisplayName: nil, userHandle: Data([1]),
            userName: nil, userDisplayName: nil, isDiscoverable: true,
            privateKey: Data("key".utf8), signCount: 0, displayName: nil, createdAt: 1
        ))

        let clear = ClearVaultUseCase(
            credentialRepository: credentialRepo,
            passkeyRepository: passkeyRepo,
            dataKeyProvider: spyKeyProvider
        )
        try await clear()

        let credentials = try await credentialRepo.listAll(sort: .updatedDesc)
        XCTAssertTrue(credentials.isEmpty, "credentials must be cleared")
        let passkey = try await passkeyRepo.findByCredentialId("c1")
        XCTAssertNil(passkey, "passkeys must be cleared")
        XCTAssertTrue(spyKeyProvider.clearAllCalled, "data key material must be cleared")
    }
}

/// Records whether `clearAll()` was called; returns a stable key for encryption.
private final class SpyDataKeyProvider: DataKeyProviding {
    private let key = SymmetricKey(size: .bits256)
    private(set) var clearAllCalled = false

    func dataKey() throws -> SymmetricKey { key }
    func clearAll() throws { clearAllCalled = true }
}
