import XCTest
import CryptoKit
import GRDB
@testable import KeyNestKit

/// Unit tests for `PasskeyRepositoryImpl` (Phase 1 task 1.5 / Req 6.4, 6.5, 6.6).
/// Uses a real `AesGcmCipher` (random key) so the encrypt-on-save /
/// decrypt-on-load round trip is genuinely exercised, against an in-memory GRDB
/// database.
final class PasskeyRepositoryTests: XCTestCase {

    private func makeRepo(now: @escaping () -> Int64 = { 7000 }) throws -> PasskeyRepositoryImpl {
        let key = SymmetricKey(size: .bits256)
        let cipher = AesGcmCipher(keyProvider: { key })
        return PasskeyRepositoryImpl(
            database: try AppDatabase(DatabaseQueue()),
            cipher: cipher,
            nowProvider: now
        )
    }

    private func sampleRequest(
        credentialId: String = "cred-1",
        rpId: String = "example.com",
        userHandle: Data = Data([0xAA, 0xBB]),
        isDiscoverable: Bool = true,
        privateKey: Data = Data("PRIVATE-KEY-BYTES".utf8),
        signCount: Int64 = 0,
        ts: Int64 = 100
    ) -> SavePasskeyRequest {
        SavePasskeyRequest(
            credentialId: credentialId,
            rpId: rpId,
            rpDisplayName: "Example RP",
            userHandle: userHandle,
            userName: "alice",
            userDisplayName: "Alice",
            isDiscoverable: isDiscoverable,
            privateKey: privateKey,
            signCount: signCount,
            displayName: nil,
            createdAt: ts
        )
    }

    func test_saveThenFind_returnsDomainPasskey_withMetadata() async throws {
        let repo = try makeRepo()
        try await repo.save(sampleRequest())

        let found = try await repo.findByCredentialId("cred-1")

        XCTAssertEqual(found?.rpId, "example.com")
        XCTAssertEqual(found?.userHandle, Data([0xAA, 0xBB]))
        XCTAssertEqual(found?.signCount, 0)
        XCTAssertEqual(found?.isDiscoverable, true)
        // The Passkey domain type structurally carries no key material.
    }

    func test_loadPrivateKey_roundTripsPlaintext() async throws {
        let repo = try makeRepo()
        let secret = Data("super-secret-pkcs8".utf8)
        try await repo.save(sampleRequest(privateKey: secret))

        let loaded = try await repo.loadPrivateKey(credentialId: "cred-1")

        XCTAssertEqual(loaded, secret)
    }

    func test_loadPrivateKey_missing_returnsNil() async throws {
        let repo = try makeRepo()
        let loaded = try await repo.loadPrivateKey(credentialId: "nope")
        XCTAssertNil(loaded)
    }

    func test_findByRpIdAndUserHandle_matchesPair() async throws {
        let repo = try makeRepo()
        try await repo.save(sampleRequest(credentialId: "c1", userHandle: Data([1])))
        try await repo.save(sampleRequest(credentialId: "c2", rpId: "other.com", userHandle: Data([2])))

        let found = try await repo.findByRpIdAndUserHandle(rpId: "example.com", userHandle: Data([1]))

        XCTAssertEqual(found?.credentialId, "c1")
    }

    func test_save_overwritesExistingRpUserHandlePair() async throws {
        // Req 6.6: re-registering for the same (rpId, userHandle) overwrites.
        let repo = try makeRepo()
        try await repo.save(sampleRequest(credentialId: "old", userHandle: Data([7])))
        try await repo.save(sampleRequest(credentialId: "new", userHandle: Data([7])))

        let old = try await repo.findByCredentialId("old")
        let new = try await repo.findByCredentialId("new")
        XCTAssertNil(old)
        XCTAssertNotNil(new)

        let discoverable = try await repo.listDiscoverableByRpId("example.com")
        XCTAssertEqual(discoverable.map { $0.credentialId }, ["new"])
    }

    func test_signWithIncrement_incrementsAndReturnsSignerResult() async throws {
        let repo = try makeRepo(now: { 8888 })
        try await repo.save(sampleRequest(signCount: 41))

        let result: String = try await repo.signWithIncrement(credentialId: "cred-1") { newCount in
            XCTAssertEqual(newCount, 42)
            return "signed@\(newCount)"
        }

        XCTAssertEqual(result, "signed@42")
        let after = try await repo.findByCredentialId("cred-1")
        XCTAssertEqual(after?.signCount, 42)
        XCTAssertEqual(after?.lastUsedAt, 8888)
    }

    func test_signWithIncrement_rollsBackWhenSignerThrows() async throws {
        struct Boom: Error {}
        let repo = try makeRepo()
        try await repo.save(sampleRequest(signCount: 5))

        do {
            _ = try await repo.signWithIncrement(credentialId: "cred-1") { _ -> String in
                throw Boom()
            }
            XCTFail("expected the signer error to propagate")
        } catch is Boom {
            // expected
        }

        let after = try await repo.findByCredentialId("cred-1")
        XCTAssertEqual(after?.signCount, 5, "counter must roll back when signing fails")
    }

    func test_signWithIncrement_missingCredential_throwsNotFound() async throws {
        let repo = try makeRepo()
        do {
            _ = try await repo.signWithIncrement(credentialId: "ghost") { _ -> String in "x" }
            XCTFail("expected RepositoryError.notFound")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .notFound)
        }
    }

    func test_delete_removesRow() async throws {
        let repo = try makeRepo()
        try await repo.save(sampleRequest())

        try await repo.delete(credentialId: "cred-1")

        XCTAssertNil(try await repo.findByCredentialId("cred-1"))
    }

    func test_listDiscoverable_excludesNonDiscoverable() async throws {
        let repo = try makeRepo()
        try await repo.save(sampleRequest(credentialId: "disc", userHandle: Data([1]), isDiscoverable: true))
        try await repo.save(sampleRequest(credentialId: "hidden", userHandle: Data([2]), isDiscoverable: false))

        let discoverable = try await repo.listDiscoverableByRpId("example.com")

        XCTAssertEqual(discoverable.map { $0.credentialId }, ["disc"])
    }
}
