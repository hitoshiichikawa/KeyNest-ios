import Foundation
import GRDB

/// GRDB-backed [PasskeyRepository]. Owns AES-GCM encryption of the private key
/// (with the shared DEK [cipher]) on `save` and its decryption on
/// `loadPrivateKey`, and projects rows to [Passkey] so secret material never
/// crosses the boundary (Req 6.4).
///
/// Crypto runs **outside** the DB transaction (encrypt before write, fetch then
/// decrypt) so the database lock is never held during cipher work.
public final class PasskeyRepositoryImpl: PasskeyRepository {
    private let database: AppDatabase
    private let cipher: Cipher
    private let nowProvider: () -> Int64

    public init(
        database: AppDatabase,
        cipher: Cipher,
        nowProvider: @escaping () -> Int64 = PasskeyRepositoryImpl.defaultNow
    ) {
        self.database = database
        self.cipher = cipher
        self.nowProvider = nowProvider
    }

    /// Wall-clock epoch millis (parity with Android `System.currentTimeMillis()`).
    public static func defaultNow() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    public func save(_ request: SavePasskeyRequest) async throws {
        let writer = database.writer
        // Encrypt before opening the transaction — never hold the DB lock during crypto.
        let blob = try cipher.encrypt(request.privateKey)
        let row = PasskeyRecord(
            credentialId: request.credentialId,
            rpId: request.rpId,
            rpDisplayName: request.rpDisplayName,
            userHandle: request.userHandle,
            userName: request.userName,
            userDisplayName: request.userDisplayName,
            isDiscoverable: request.isDiscoverable,
            encryptedPrivateKey: blob.ciphertext,
            privateKeyIv: blob.iv,
            signCount: request.signCount,
            displayName: request.displayName,
            createdAt: request.createdAt,
            lastUsedAt: nil
        )
        let rpId = request.rpId
        let userHandle = request.userHandle
        try await writer.write { db in
            // Req 6.6: a registration for an existing (rpId, userHandle) pair
            // overwrites the prior passkey rather than creating a duplicate.
            try PasskeyRecord
                .filter(PasskeyRecord.Columns.rpId == rpId && PasskeyRecord.Columns.userHandle == userHandle)
                .deleteAll(db)
            try row.insert(db)
        }
    }

    public func findByCredentialId(_ credentialId: String) async throws -> Passkey? {
        let writer = database.writer
        return try await writer.read { db in
            try PasskeyRecord.fetchOne(db, key: credentialId)?.toDomain()
        }
    }

    public func findByRpIdAndUserHandle(rpId: String, userHandle: Data) async throws -> Passkey? {
        let writer = database.writer
        return try await writer.read { db in
            try PasskeyRecord
                .filter(PasskeyRecord.Columns.rpId == rpId && PasskeyRecord.Columns.userHandle == userHandle)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func listDiscoverableByRpId(_ rpId: String) async throws -> [Passkey] {
        let writer = database.writer
        return try await writer.read { db in
            try PasskeyRecord
                .filter(PasskeyRecord.Columns.rpId == rpId)
                .filter(PasskeyRecord.Columns.isDiscoverable == true)
                .order(sql: "(last_used_at IS NULL) ASC, last_used_at DESC, created_at DESC")
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func signWithIncrement<T: Sendable>(
        credentialId: String,
        sign: @Sendable @escaping (_ newSignCount: Int64) throws -> T
    ) async throws -> T {
        let writer = database.writer
        let timestamp = nowProvider()
        return try await writer.write { db in
            try db.execute(
                sql: "UPDATE passkeys SET sign_count = sign_count + 1, last_used_at = ? WHERE credential_id = ?",
                arguments: [timestamp, credentialId]
            )
            guard let row = try PasskeyRecord.fetchOne(db, key: credentialId) else {
                throw RepositoryError.notFound
            }
            // If `sign` throws, the transaction rolls back and the counter bump
            // is undone (Req 6.5).
            return try sign(row.signCount)
        }
    }

    public func loadPrivateKey(credentialId: String) async throws -> Data? {
        let writer = database.writer
        let row = try await writer.read { db in
            try PasskeyRecord.fetchOne(db, key: credentialId)
        }
        guard let row else { return nil }
        // Decrypt outside the transaction. A GCM auth-tag failure propagates.
        return try cipher.decrypt(EncryptedBlob(iv: row.privateKeyIv, ciphertext: row.encryptedPrivateKey))
    }

    public func delete(credentialId: String) async throws {
        let writer = database.writer
        try await writer.write { db in
            _ = try PasskeyRecord.deleteOne(db, key: credentialId)
        }
    }

    public func clearAll() async throws {
        let writer = database.writer
        try await writer.write { db in
            _ = try PasskeyRecord.deleteAll(db)
        }
    }

    public func observeAll() -> AsyncThrowingStream<[Passkey], Error> {
        database.observe { db in
            try PasskeyRecord
                .all()
                .order(sql: "(last_used_at IS NULL) ASC, last_used_at DESC, created_at DESC")
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}

// MARK: - Mapping (storage → domain)

private extension PasskeyRecord {
    /// Drops `encryptedPrivateKey` / `privateKeyIv` so secret material stays
    /// bounded to the data layer (Req 6.4).
    func toDomain() -> Passkey {
        Passkey(
            credentialId: credentialId,
            rpId: rpId,
            rpDisplayName: rpDisplayName,
            userHandle: userHandle,
            userName: userName,
            userDisplayName: userDisplayName,
            isDiscoverable: isDiscoverable,
            signCount: signCount,
            displayName: displayName,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt
        )
    }
}
