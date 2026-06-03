import XCTest
import GRDB
@testable import KeyNestKit

/// Unit tests for the async-stream observation use cases (Phase 2.2). Verifies
/// the GRDB `ValueObservation` → `AsyncThrowingStream` bridge by asserting the
/// first emission reflects the current database state.
final class CredentialObservationUseCaseTests: XCTestCase {

    private func makeRepo() throws -> CredentialRepositoryImpl {
        CredentialRepositoryImpl(database: try AppDatabase(DatabaseQueue()))
    }

    private func sample(_ serviceIdentifier: String, label: String, ts: Int64) -> EncryptedCredentialRecord {
        EncryptedCredentialRecord(
            id: CredentialId(0), serviceIdentifier: serviceIdentifier, username: "u", label: label,
            passwordCiphertext: Data([1]), passwordIv: Data(repeating: 0, count: 12),
            createdAt: ts, updatedAt: ts
        )
    }

    func test_listCredentials_firstEmissionReflectsCurrentState() async throws {
        let repo = try makeRepo()
        _ = try await repo.save(sample("zebra.com", label: "Zebra", ts: 100))
        _ = try await repo.save(sample("apple.com", label: "Apple", ts: 200))

        let list = try await firstEmission(ListCredentialsUseCase(repository: repo)(order: .updatedDesc))

        XCTAssertEqual(list.map { $0.serviceIdentifier }, ["apple.com", "zebra.com"])  // newest first
    }

    func test_observeVaultMetadata_firstEmissionHasCountAndLatest() async throws {
        let repo = try makeRepo()
        _ = try await repo.save(sample("a.com", label: "A", ts: 100))
        _ = try await repo.save(sample("b.com", label: "B", ts: 200))

        let metadata = try await firstEmission(ObserveVaultMetadataUseCase(repository: repo)())

        XCTAssertEqual(metadata.count, 2)
        XCTAssertEqual(metadata.latestUpdatedAt, 200)
    }

    func test_observeVaultMetadata_emptyVault_hasNilLatest() async throws {
        let repo = try makeRepo()
        let metadata = try await firstEmission(ObserveVaultMetadataUseCase(repository: repo)())
        XCTAssertEqual(metadata.count, 0)
        XCTAssertNil(metadata.latestUpdatedAt)
    }

    func test_observeRecentlyUsed_excludesNeverUsed() async throws {
        let repo = try makeRepo()
        let usedId = try await repo.save(sample("used.com", label: "Used", ts: 100))
        _ = try await repo.save(sample("never.com", label: "Never", ts: 200))
        try await repo.markUsed(usedId, timestamp: 999)

        let recent = try await firstEmission(ObserveRecentlyUsedUseCase(repository: repo)())

        XCTAssertEqual(recent.map { $0.serviceIdentifier }, ["used.com"])
    }
}

/// Returns the first element emitted by an async stream, then stops consuming.
private func firstEmission<S: AsyncSequence>(_ sequence: S) async throws -> S.Element {
    for try await value in sequence {
        return value
    }
    throw ObservationTestError.noEmission
}

private enum ObservationTestError: Error { case noEmission }
