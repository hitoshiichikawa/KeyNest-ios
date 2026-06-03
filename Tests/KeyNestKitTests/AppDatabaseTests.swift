import XCTest
import GRDB
@testable import KeyNestKit

/// Unit tests for `AppDatabase` (Phase 1 task 1.4). Verifies the collapsed `v1`
/// migration creates both tables and the uniqueness constraint that backs
/// Req 6.6. Runs against an in-memory `DatabaseQueue`.
final class AppDatabaseTests: XCTestCase {

    func test_v1Migration_createsCredentialsAndPasskeysTables() throws {
        let database = try AppDatabase(DatabaseQueue())

        try database.writer.read { db in
            XCTAssertTrue(try db.tableExists("credentials"))
            XCTAssertTrue(try db.tableExists("passkeys"))
        }
    }

    func test_v1Migration_passkeysHasUniqueRpUserHandleIndex() throws {
        let database = try AppDatabase(DatabaseQueue())

        try database.writer.read { db in
            let indexes = try db.indexes(on: "passkeys")
            let uniquePair = indexes.first {
                $0.isUnique && $0.columns == ["rp_id", "user_handle"]
            }
            XCTAssertNotNil(uniquePair, "expected a UNIQUE index on (rp_id, user_handle)")
        }
    }

    func test_v1Migration_credentialsServiceIndexExists() throws {
        let database = try AppDatabase(DatabaseQueue())

        try database.writer.read { db in
            let indexes = try db.indexes(on: "credentials")
            XCTAssertTrue(indexes.contains { $0.columns == ["service_identifier"] })
        }
    }
}
