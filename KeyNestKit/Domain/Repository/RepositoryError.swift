import Foundation

/// Errors surfaced across the repository boundary. Kept deliberately small —
/// storage-engine errors (GRDB / SQLite) propagate verbatim; this enum only
/// names the domain-level conditions callers branch on.
public enum RepositoryError: Error, Equatable {
    /// A lookup by id/key found no matching row (e.g. `duplicate` of a
    /// credential that was deleted in a race, or `signWithIncrement` against a
    /// passkey that no longer exists).
    case notFound
}
