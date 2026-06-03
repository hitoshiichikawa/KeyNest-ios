import Foundation
import GRDB

/// Errors raised while opening the shared database.
public enum AppDatabaseError: Error {
    /// The App Group container is not provisioned (entitlement / provisioning
    /// misconfiguration). Callers should treat this as fatal at startup.
    case appGroupUnavailable
}

/// Owns the GRDB connection to the KeyNest vault and runs schema migrations.
///
/// iOS equivalent of KeyNest Android's `KeyNestDatabase` (Room). The vault lives
/// in the **App Group** container so the main app and the AutoFill extension
/// read/write the same file (Req 1.2). A `DatabasePool` (WAL) is used so the two
/// processes can read concurrently; a busy timeout absorbs cross-process write
/// contention.
///
/// Migration policy mirrors Android: destructive fallback is **never** enabled —
/// silently losing the vault is worse than a startup error. Because there are no
/// existing installs, Room's v1→v5 history is collapsed into a single GRDB `v1`
/// migration that creates the `credentials` and `passkeys` tables directly
/// (design §Data). The `passkeys` table drops Android's `keyAlias` column: iOS
/// encrypts every row with the single shared DEK (確定事項 2).
///
/// > Verify on Mac/device: WAL across an App Group works on device; if the host
/// > app is suspended while holding the lock, GRDB's database-suspension
/// > handling (`0xDEAD10CC` avoidance) may need wiring in a later phase. Unit
/// > tests use an in-memory `DatabaseQueue` via [init(_:)].
public final class AppDatabase {
    /// The GRDB writer. `any DatabaseWriter` so tests can inject an in-memory
    /// `DatabaseQueue` while production uses a `DatabasePool`.
    public let writer: any DatabaseWriter

    /// Wraps an existing writer and migrates it. Tests pass `DatabaseQueue()`
    /// (in-memory); [makeShared] passes the App Group `DatabasePool`.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Bridges a GRDB `ValueObservation` to a Foundation `AsyncThrowingStream`
    /// so the domain repositories can expose DB-change observation without
    /// leaking GRDB types across the boundary. The stream emits the current
    /// value immediately, then again on every committed change; cancelling the
    /// consumer stops the underlying observation.
    public func observe<T: Sendable>(
        _ fetch: @escaping @Sendable (Database) throws -> T
    ) -> AsyncThrowingStream<T, Error> {
        let observation = ValueObservation.tracking(fetch)
        let reader = writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: reader) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Opens the shared App Group database (creating it on first launch) and
    /// migrates it.
    public static func makeShared() throws -> AppDatabase {
        guard let url = AppGroup.databaseURL() else {
            throw AppDatabaseError.appGroupUnavailable
        }
        var configuration = Configuration()
        // Cross-process write contention (app vs extension): wait rather than
        // fail fast on SQLITE_BUSY.
        configuration.busyMode = .timeout(10)
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        // Allow the extension to read the vault after first unlock (it may run
        // while the device is locked). Best-effort: never block startup on it.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        return try AppDatabase(pool)
    }

    /// Single collapsed migration (no prior installs to migrate from).
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "credentials") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("service_identifier", .text).notNull()
                t.column("username", .text).notNull()
                t.column("label", .text).notNull()
                t.column("password_ciphertext", .blob).notNull()
                t.column("password_iv", .blob).notNull()
                t.column("custom_fields_ciphertext", .blob).notNull().defaults(to: Data())
                t.column("custom_fields_iv", .blob).notNull().defaults(to: Data())
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("last_used_at", .integer)
            }
            try db.create(
                index: "idx_credentials_service",
                on: "credentials",
                columns: ["service_identifier"]
            )

            try db.create(table: "passkeys") { t in
                // base64url WebAuthn credentialId (produced by the ceremony, not SQLite).
                t.primaryKey("credential_id", .text)
                t.column("rp_id", .text).notNull()
                t.column("rp_display_name", .text)
                t.column("user_handle", .blob).notNull()
                t.column("user_name", .text)
                t.column("user_display_name", .text)
                t.column("is_discoverable", .boolean).notNull().defaults(to: true)
                t.column("encrypted_private_key", .blob).notNull()
                t.column("private_key_iv", .blob).notNull()
                t.column("sign_count", .integer).notNull().defaults(to: 0)
                t.column("display_name", .text)
                t.column("created_at", .integer).notNull()
                t.column("last_used_at", .integer)
            }
            try db.create(index: "idx_passkeys_rp", on: "passkeys", columns: ["rp_id"])
            // A relying party cannot store two PassKeys for the same user handle (Req 6.6).
            try db.create(
                index: "idx_passkeys_rp_user",
                on: "passkeys",
                columns: ["rp_id", "user_handle"],
                options: [.unique]
            )
        }
        return migrator
    }
}
