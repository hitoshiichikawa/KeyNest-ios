import Foundation

/// Aggregated, non-sensitive metadata about the credential vault. Port of
/// KeyNest Android's `VaultMetadata`.
///
/// Carries only aggregate values (count + most-recent timestamp) — never
/// individual credential fields — so the Settings screen can surface it without
/// exposing label / username / serviceIdentifier / password (NFR 1.2). The query
/// that produces it is `COUNT(*)` / `MAX(updated_at)`, so no row contents are
/// materialised.
///
/// Invariant: when [count] == 0, [latestUpdatedAt] is nil (`MAX` over an empty
/// table is NULL); the UI shows a placeholder instead of a date.
public struct VaultMetadata: Sendable, Equatable {
    /// Total number of saved credentials (>= 0).
    public let count: Int
    /// Most recent `updated_at` across all credentials (epoch millis, UTC), or
    /// nil when the vault is empty.
    public let latestUpdatedAt: Int64?

    public init(count: Int, latestUpdatedAt: Int64?) {
        self.count = count
        self.latestUpdatedAt = latestUpdatedAt
    }
}
