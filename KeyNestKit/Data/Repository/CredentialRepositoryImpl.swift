import Foundation
import GRDB

/// GRDB-backed [CredentialRepository]. Maps between [CredentialRecord] (storage)
/// and the domain types [EncryptedCredentialRecord] / [Credential]. Holds no
/// cipher: passwords/custom-fields arrive already encrypted as blobs (the use
/// cases own encryption), so the repository only persists bytes (NFR — no
/// plaintext at the persistence layer).
public final class CredentialRepositoryImpl: CredentialRepository {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ record: EncryptedCredentialRecord) async throws -> CredentialId {
        let writer = database.writer
        let row = record.toRecord(idOverride: nil)  // ignore record.id; SQLite assigns
        return try await writer.write { db in
            var inserting = row
            try inserting.insert(db)
            return CredentialId(inserting.id ?? db.lastInsertedRowID)
        }
    }

    public func update(_ record: EncryptedCredentialRecord) async throws {
        let writer = database.writer
        let row = record.toRecord(idOverride: record.id.value)
        try await writer.write { db in
            try row.update(db)
        }
    }

    public func delete(_ id: CredentialId) async throws {
        let writer = database.writer
        let key = id.value
        try await writer.write { db in
            _ = try CredentialRecord.deleteOne(db, key: key)
        }
    }

    public func findById(_ id: CredentialId) async throws -> EncryptedCredentialRecord? {
        let writer = database.writer
        let key = id.value
        return try await writer.read { db in
            try CredentialRecord.fetchOne(db, key: key)?.toEncryptedRecord()
        }
    }

    public func findByServiceIdentifier(_ serviceIdentifier: String) async throws -> [EncryptedCredentialRecord] {
        let writer = database.writer
        return try await writer.read { db in
            try CredentialRecord
                .filter(CredentialRecord.Columns.serviceIdentifier == serviceIdentifier)
                .order(sql: "updated_at DESC, label ASC")
                .fetchAll(db)
                .map { $0.toEncryptedRecord() }
        }
    }

    public func listAll(sort: CredentialSortOrder) async throws -> [Credential] {
        let writer = database.writer
        let orderSQL = Self.orderSQL(for: sort)
        return try await writer.read { db in
            try CredentialRecord
                .all()
                .order(sql: orderSQL)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func markUsed(_ id: CredentialId, timestamp: Int64) async throws {
        let writer = database.writer
        let key = id.value
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE credentials SET last_used_at = ? WHERE id = ?",
                arguments: [timestamp, key]
            )
        }
    }

    public func duplicate(_ sourceId: CredentialId, timestamp: Int64) async throws -> CredentialId {
        let writer = database.writer
        let key = sourceId.value
        return try await writer.write { db in
            guard var copy = try CredentialRecord.fetchOne(db, key: key) else {
                throw RepositoryError.notFound
            }
            // Inherit ciphertext/IV unchanged: no decrypt → re-encrypt, so no
            // plaintext is materialised during a duplicate (NFR 1.1).
            copy.id = nil
            copy.createdAt = timestamp
            copy.updatedAt = timestamp
            copy.lastUsedAt = nil  // a duplicate is "fresh / never used"
            try copy.insert(db)
            return CredentialId(copy.id ?? db.lastInsertedRowID)
        }
    }

    public func clearAll() async throws {
        let writer = database.writer
        try await writer.write { db in
            _ = try CredentialRecord.deleteAll(db)
        }
    }

    public func observeBySort(_ sort: CredentialSortOrder) -> AsyncThrowingStream<[Credential], Error> {
        let orderSQL = Self.orderSQL(for: sort)
        return database.observe { db in
            try CredentialRecord
                .all()
                .order(sql: orderSQL)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func observeRecentlyUsed(limit: Int) -> AsyncThrowingStream<[Credential], Error> {
        database.observe { db in
            try CredentialRecord
                .filter(sql: "last_used_at IS NOT NULL")
                .order(sql: "last_used_at DESC")
                .limit(limit)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func observeMetadata() -> AsyncThrowingStream<VaultMetadata, Error> {
        database.observe { db in
            let count = try CredentialRecord.fetchCount(db)
            let latest = try Int64.fetchOne(db, sql: "SELECT MAX(updated_at) FROM credentials")
            return VaultMetadata(count: count, latestUpdatedAt: latest)
        }
    }

    private static func orderSQL(for sort: CredentialSortOrder) -> String {
        switch sort {
        case .updatedDesc: return "updated_at DESC, label ASC"
        case .labelAsc: return "label COLLATE NOCASE ASC, updated_at DESC"
        case .domainAsc: return "service_identifier COLLATE NOCASE ASC, updated_at DESC"
        }
    }
}

// MARK: - Mapping (storage ⇄ domain)

private extension EncryptedCredentialRecord {
    func toRecord(idOverride: Int64?) -> CredentialRecord {
        CredentialRecord(
            id: idOverride,
            serviceIdentifier: serviceIdentifier,
            username: username,
            label: label,
            passwordCiphertext: passwordCiphertext,
            passwordIv: passwordIv,
            customFieldsCiphertext: customFieldsCiphertext,
            customFieldsIv: customFieldsIv,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt
        )
    }
}

private extension CredentialRecord {
    func toEncryptedRecord() -> EncryptedCredentialRecord {
        EncryptedCredentialRecord(
            id: CredentialId(id ?? 0),
            serviceIdentifier: serviceIdentifier,
            username: username,
            label: label,
            passwordCiphertext: passwordCiphertext,
            passwordIv: passwordIv,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt,
            customFieldsCiphertext: customFieldsCiphertext,
            customFieldsIv: customFieldsIv
        )
    }

    func toDomain() -> Credential {
        Credential(
            id: CredentialId(id ?? 0),
            serviceIdentifier: serviceIdentifier,
            username: username,
            label: label,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt
        )
    }
}
