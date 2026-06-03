import Foundation

/// Domain port for PassKey persistence. Port of KeyNest Android's
/// `PasskeyRepository`, adapted to iOS:
/// - Lookup / list APIs return [Passkey] domain aggregates, never the GRDB row,
///   so the encrypted private key + IV never leak across the boundary (Req 6.4).
/// - The repository **owns** AES-GCM encryption of [SavePasskeyRequest.privateKey]
///   before INSERT (with the shared DEK; no per-key alias — 確定事項 2).
/// - [signWithIncrement] wraps "increment signCount → read back → sign" in one
///   DB transaction so the counter rolls back if signing throws (Req 6.5).
/// - Reactive observers are out of scope this phase (snapshot reads only).
public protocol PasskeyRepository {
    /// Encrypts `request.privateKey` and inserts the row. Per Req 6.6, a save
    /// for an existing `(rpId, userHandle)` pair overwrites the prior passkey.
    /// The caller wipes `request.privateKey` after this returns (NFR 1.1).
    func save(_ request: SavePasskeyRequest) async throws

    /// Looks up a PassKey by WebAuthn credentialId, or nil. Used by
    /// excludeCredentials checks and the `allowCredentials` assertion path.
    func findByCredentialId(_ credentialId: String) async throws -> Passkey?

    /// Looks up by `(rpId, userHandle)` (0 or 1 row — the pair is UNIQUE). Used
    /// during registration to detect/overwrite duplicates.
    func findByRpIdAndUserHandle(rpId: String, userHandle: Data) async throws -> Passkey?

    /// Discoverable PassKeys for [rpId] (usernameless login), ordered
    /// most-recently-used first, never-used last, `createdAt DESC` tiebreak.
    func listDiscoverableByRpId(_ rpId: String) async throws -> [Passkey]

    /// Atomized "increment signCount → read back → sign". Opens a DB
    /// transaction, bumps `signCount` and stamps `lastUsedAt`, passes the new
    /// count to [sign], commits on success, and rolls back on throw so the
    /// counter never advances past a failed signature (Req 6.5).
    ///
    /// Throws [RepositoryError.notFound] when [credentialId] has no row.
    func signWithIncrement<T: Sendable>(
        credentialId: String,
        sign: @Sendable @escaping (_ newSignCount: Int64) throws -> T
    ) async throws -> T

    /// Decrypts and returns the plaintext private-key bytes for [credentialId],
    /// or nil when absent. A GCM auth-tag failure propagates (no silent fail).
    /// The caller wipes the returned buffer immediately after use (NFR 1.1).
    func loadPrivateKey(credentialId: String) async throws -> Data?

    /// Deletes the PassKey row with [credentialId], if present (no-op otherwise).
    func delete(credentialId: String) async throws

    /// Removes every PassKey in a single statement. Idempotent. Used by the
    /// Danger Zone "clear vault" flow (Req 7.4).
    func clearAll() async throws

    /// Observes all stored PassKeys as [Passkey] domain aggregates, ordered
    /// most-recently-used first (never-used last), `created_at DESC` tiebreak.
    /// Emits the current value immediately, then on every committed change.
    func observeAll() -> AsyncThrowingStream<[Passkey], Error>
}
