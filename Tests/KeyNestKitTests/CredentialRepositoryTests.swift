import XCTest
import GRDB
@testable import KeyNestKit

/// Unit tests for `CredentialRepositoryImpl` (Phase 1 task 1.5 / Req 2.2).
/// Exercises CRUD, `findByServiceIdentifier`, sort variants, markUsed,
/// duplicate (ciphertext inheritance + timestamp reset) and clearAll against an
/// in-memory GRDB database.
final class CredentialRepositoryTests: XCTestCase {

    private func makeRepo() throws -> CredentialRepositoryImpl {
        CredentialRepositoryImpl(database: try AppDatabase(DatabaseQueue()))
    }

    private func sampleRecord(
        serviceIdentifier: String = "example.com",
        username: String = "alice",
        label: String = "Example",
        ts: Int64 = 1000
    ) -> EncryptedCredentialRecord {
        EncryptedCredentialRecord(
            id: CredentialId(0),
            serviceIdentifier: serviceIdentifier,
            username: username,
            label: label,
            passwordCiphertext: Data([1, 2, 3]),
            passwordIv: Data(repeating: 9, count: 12),
            createdAt: ts,
            updatedAt: ts,
            lastUsedAt: nil,
            customFieldsCiphertext: Data([4, 5]),
            customFieldsIv: Data(repeating: 8, count: 12)
        )
    }

    func test_saveThenFindById_roundTripsAllFields() async throws {
        let repo = try makeRepo()
        let id = try await repo.save(sampleRecord())

        let found = try await repo.findById(id)

        XCTAssertEqual(found?.id, id)
        XCTAssertEqual(found?.serviceIdentifier, "example.com")
        XCTAssertEqual(found?.username, "alice")
        XCTAssertEqual(found?.passwordCiphertext, Data([1, 2, 3]))
        XCTAssertEqual(found?.passwordIv, Data(repeating: 9, count: 12))
        XCTAssertEqual(found?.customFieldsCiphertext, Data([4, 5]))
    }

    func test_findByServiceIdentifier_returnsOnlyMatches_orderedUpdatedDesc() async throws {
        let repo = try makeRepo()
        _ = try await repo.save(sampleRecord(serviceIdentifier: "a.com", label: "A1", ts: 100))
        _ = try await repo.save(sampleRecord(serviceIdentifier: "a.com", label: "A2", ts: 200))
        _ = try await repo.save(sampleRecord(serviceIdentifier: "b.com", label: "B", ts: 300))

        let matches = try await repo.findByServiceIdentifier("a.com")

        XCTAssertEqual(matches.map { $0.label }, ["A2", "A1"])  // updated_at DESC
    }

    func test_update_changesStoredFields() async throws {
        let repo = try makeRepo()
        let id = try await repo.save(sampleRecord(label: "Old"))
        let original = try await XCTUnwrapAsync(repo.findById(id))

        let edited = EncryptedCredentialRecord(
            id: id,
            serviceIdentifier: original.serviceIdentifier,
            username: original.username,
            label: "New",
            passwordCiphertext: original.passwordCiphertext,
            passwordIv: original.passwordIv,
            createdAt: original.createdAt,
            updatedAt: 5000,
            lastUsedAt: original.lastUsedAt,
            customFieldsCiphertext: original.customFieldsCiphertext,
            customFieldsIv: original.customFieldsIv
        )
        try await repo.update(edited)

        let found = try await repo.findById(id)
        XCTAssertEqual(found?.label, "New")
        XCTAssertEqual(found?.updatedAt, 5000)
    }

    func test_delete_removesRow() async throws {
        let repo = try makeRepo()
        let id = try await repo.save(sampleRecord())

        try await repo.delete(id)

        let found = try await repo.findById(id)
        XCTAssertNil(found)
    }

    func test_markUsed_setsLastUsedAt() async throws {
        let repo = try makeRepo()
        let id = try await repo.save(sampleRecord())

        try await repo.markUsed(id, timestamp: 4242)

        let found = try await repo.findById(id)
        XCTAssertEqual(found?.lastUsedAt, 4242)
    }

    func test_duplicate_inheritsCiphertext_resetsTimestamps_clearsLastUsed() async throws {
        let repo = try makeRepo()
        let id = try await repo.save(sampleRecord(ts: 100))
        try await repo.markUsed(id, timestamp: 555)

        let newId = try await repo.duplicate(id, timestamp: 9000)

        XCTAssertNotEqual(newId, id)
        let copy = try await repo.findById(newId)
        XCTAssertEqual(copy?.passwordCiphertext, Data([1, 2, 3]))  // inherited, not re-encrypted
        XCTAssertEqual(copy?.createdAt, 9000)
        XCTAssertEqual(copy?.updatedAt, 9000)
        XCTAssertNil(copy?.lastUsedAt)  // a duplicate is "fresh"
    }

    func test_duplicate_missingSource_throwsNotFound() async throws {
        let repo = try makeRepo()
        do {
            _ = try await repo.duplicate(CredentialId(999), timestamp: 1)
            XCTFail("expected RepositoryError.notFound")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .notFound)
        }
    }

    func test_clearAll_emptiesVault() async throws {
        let repo = try makeRepo()
        _ = try await repo.save(sampleRecord(serviceIdentifier: "a.com"))
        _ = try await repo.save(sampleRecord(serviceIdentifier: "b.com"))

        try await repo.clearAll()

        let all = try await repo.listAll(sort: .updatedDesc)
        XCTAssertTrue(all.isEmpty)
    }

    func test_listAll_sortVariants() async throws {
        let repo = try makeRepo()
        _ = try await repo.save(sampleRecord(serviceIdentifier: "zebra.com", label: "Zebra", ts: 100))
        _ = try await repo.save(sampleRecord(serviceIdentifier: "apple.com", label: "Apple", ts: 200))

        let byUpdated = try await repo.listAll(sort: .updatedDesc)
        XCTAssertEqual(byUpdated.map { $0.label }, ["Apple", "Zebra"])  // newest first

        let byLabel = try await repo.listAll(sort: .labelAsc)
        XCTAssertEqual(byLabel.map { $0.label }, ["Apple", "Zebra"])  // alphabetical

        let byDomain = try await repo.listAll(sort: .domainAsc)
        XCTAssertEqual(byDomain.map { $0.serviceIdentifier }, ["apple.com", "zebra.com"])
    }
}

/// Async `XCTUnwrap` helper (XCTUnwrap itself is sync; this awaits then unwraps).
func XCTUnwrapAsync<T>(
    _ expression: @autoclosure () async throws -> T?,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, file: file, line: line)
}
