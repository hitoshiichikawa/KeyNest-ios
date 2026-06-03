import Foundation

/// Domain-side abstraction over credential persistence. The implementation
/// (`CredentialRepositoryImpl`) maps GRDB rows to/from [EncryptedCredentialRecord]
/// / [Credential]. The domain layer never sees plaintext passwords —
/// encryption / decryption is the cipher's responsibility, performed by the use
/// cases, not here.
///
/// Port of KeyNest Android's `CredentialRepository`, adapted to iOS:
/// - `findByPackage` → [findByServiceIdentifier] (domain matching).
/// - Reactive observers (Kotlin `Flow`) are intentionally **not** included in
///   this phase; reads are snapshot-based ([listAll]). The reactive variants
///   land with the use-case / UI layers that consume them.
/// - Kotlin `Result<>` / sealed failures → Swift `throws` (`RepositoryError`).
public protocol CredentialRepository {
    /// Inserts a new credential (ignoring `record.id`) and returns the assigned id.
    func save(_ record: EncryptedCredentialRecord) async throws -> CredentialId

    /// Updates the credential identified by `record.id`.
    func update(_ record: EncryptedCredentialRecord) async throws

    /// Deletes the credential with [id], if present (no-op otherwise).
    func delete(_ id: CredentialId) async throws

    /// Returns the credential matching [id], or nil.
    func findById(_ id: CredentialId) async throws -> EncryptedCredentialRecord?

    /// All credentials whose target matches [serviceIdentifier] (may be empty),
    /// ordered `updated_at DESC, label ASC`. Primary autofill lookup path.
    func findByServiceIdentifier(_ serviceIdentifier: String) async throws -> [EncryptedCredentialRecord]

    /// Snapshot of all credentials as the lightweight [Credential] aggregate
    /// (no ciphertext), ordered per [sort]. Used by the credential list and the
    /// AutoFill identity-store sync.
    func listAll(sort: CredentialSortOrder) async throws -> [Credential]

    /// Stamps [timestamp] onto `lastUsedAt` of the credential with [id].
    /// Silent no-op if the row was deleted in a race.
    func markUsed(_ id: CredentialId, timestamp: Int64) async throws

    /// Copies the credential at [sourceId], inheriting its ciphertext/IV
    /// unchanged (no decrypt → re-encrypt cycle). Timestamps reset to
    /// [timestamp]; `lastUsedAt` cleared. Throws [RepositoryError.notFound] if
    /// the source is gone.
    func duplicate(_ sourceId: CredentialId, timestamp: Int64) async throws -> CredentialId

    /// Removes every credential in a single statement. Idempotent. Used by the
    /// Danger Zone "clear vault" flow; touches no plaintext.
    func clearAll() async throws

    // MARK: - Observation (async streams)
    //
    // Each stream emits the current value immediately, then again on every
    // committed change. Backed by GRDB `ValueObservation`; the GRDB type is
    // bridged to `AsyncThrowingStream` so the domain stays storage-agnostic.

    /// Observes the credential list (lightweight [Credential], no ciphertext)
    /// ordered per [sort].
    func observeBySort(_ sort: CredentialSortOrder) -> AsyncThrowingStream<[Credential], Error>

    /// Observes the top-[limit] most-recently-used credentials (never-used rows
    /// excluded), `last_used_at DESC`.
    func observeRecentlyUsed(limit: Int) -> AsyncThrowingStream<[Credential], Error>

    /// Observes aggregate [VaultMetadata] (count + most-recent `updated_at`).
    func observeMetadata() -> AsyncThrowingStream<VaultMetadata, Error>
}
