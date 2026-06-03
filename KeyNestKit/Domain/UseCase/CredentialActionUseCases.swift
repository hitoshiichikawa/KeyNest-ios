import Foundation

/// Deletes a credential by id. Idempotent (deleting a missing id is a no-op).
/// Port of KeyNest Android's `DeleteCredentialUseCase`. Storage errors propagate.
public struct DeleteCredentialUseCase {
    private let repository: CredentialRepository

    public init(repository: CredentialRepository) {
        self.repository = repository
    }

    public func callAsFunction(_ id: CredentialId) async throws {
        try await repository.delete(id)
    }
}

/// Creates a copy of an existing credential, inheriting its ciphertext/IV
/// verbatim (never decrypts), resetting timestamps and clearing `lastUsedAt`.
/// Port of KeyNest Android's `DuplicateCredentialUseCase`. Throws
/// `RepositoryError.notFound` when the source row is gone.
public struct DuplicateCredentialUseCase {
    private let repository: CredentialRepository
    private let now: () -> Int64

    public init(
        repository: CredentialRepository,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.repository = repository
        self.now = now
    }

    @discardableResult
    public func callAsFunction(_ sourceId: CredentialId) async throws -> CredentialId {
        try await repository.duplicate(sourceId, timestamp: now())
    }
}

/// Stamps the current time onto a credential's `lastUsedAt` (called from the
/// autofill flow once fill succeeds). Port of KeyNest Android's
/// `MarkCredentialUsedUseCase`. Silent no-op if the row was deleted in a race;
/// storage errors propagate.
public struct MarkCredentialUsedUseCase {
    private let repository: CredentialRepository
    private let now: () -> Int64

    public init(
        repository: CredentialRepository,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.repository = repository
        self.now = now
    }

    public func callAsFunction(_ id: CredentialId) async throws {
        try await repository.markUsed(id, timestamp: now())
    }
}
