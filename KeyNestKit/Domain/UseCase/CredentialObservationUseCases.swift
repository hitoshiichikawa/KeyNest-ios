import Foundation

/// Observes the credential list (lightweight [Credential], no ciphertext) for a
/// given sort order. Port of KeyNest Android's `ListCredentialsUseCase` (Kotlin
/// `Flow` → Swift `AsyncThrowingStream`). Keeps view models off the repository.
public struct ListCredentialsUseCase {
    private let repository: CredentialRepository

    public init(repository: CredentialRepository) {
        self.repository = repository
    }

    public func callAsFunction(
        order: CredentialSortOrder = .updatedDesc
    ) -> AsyncThrowingStream<[Credential], Error> {
        repository.observeBySort(order)
    }
}

/// Observes the top-N most-recently-used credentials for the carousel. Limit is
/// fixed at 5 (parity with KeyNest Android's `ObserveRecentlyUsedUseCase`).
public struct ObserveRecentlyUsedUseCase {
    private static let limit = 5
    private let repository: CredentialRepository

    public init(repository: CredentialRepository) {
        self.repository = repository
    }

    public func callAsFunction() -> AsyncThrowingStream<[Credential], Error> {
        repository.observeRecentlyUsed(limit: Self.limit)
    }
}

/// Observes aggregate [VaultMetadata] (count + most-recent update) for the
/// Settings screen. Port of KeyNest Android's `ObserveVaultMetadataUseCase`.
public struct ObserveVaultMetadataUseCase {
    private let repository: CredentialRepository

    public init(repository: CredentialRepository) {
        self.repository = repository
    }

    public func callAsFunction() -> AsyncThrowingStream<VaultMetadata, Error> {
        repository.observeMetadata()
    }
}
