import Foundation

/// Observes all stored PassKeys as [Passkey] domain aggregates (no secret
/// material). Port of KeyNest Android's `ListPasskeysUseCase`, returning the
/// domain type rather than a UI display model — the Phase 3 list layer maps to
/// its own presentation type. Kotlin `Flow` → Swift `AsyncThrowingStream`.
public struct ListPasskeysUseCase {
    private let repository: PasskeyRepository

    public init(repository: PasskeyRepository) {
        self.repository = repository
    }

    public func callAsFunction() -> AsyncThrowingStream<[Passkey], Error> {
        repository.observeAll()
    }
}
