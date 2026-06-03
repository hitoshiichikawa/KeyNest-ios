import Foundation

/// Strongly typed credential identifier (parity with KeyNest `CredentialId`).
public struct CredentialId: Hashable, Sendable {
    public let value: Int64
    public init(_ value: Int64) { self.value = value }
}

/// Domain representation of a saved credential.
///
/// Differences from KeyNest's `Credential`:
/// - `packageName` → `serviceIdentifier` (a normalized web domain — iOS matches
///   AutoFill candidates by `ASCredentialServiceIdentifier`, not by app package).
/// - `signatureSha256` / `signatureCapturedAt` removed: iOS has no per-app
///   signing-certificate match for AutoFill, so the whole signature concept is dropped.
///
/// The plaintext password is intentionally absent — it lives only on the
/// short-lived `PlaintextCredential` after an explicit unlock.
public struct Credential: Identifiable, Sendable {
    public let id: CredentialId
    /// Normalized target domain, e.g. "example.com".
    public let serviceIdentifier: String
    public let username: String
    public let label: String
    public let createdAt: Int64
    public let updatedAt: Int64
    /// Epoch millis of the most recent autofill consumption; nil = never used
    /// (excluded from the "recently used" section, parity with KeyNest Req 3.3/3.4).
    public let lastUsedAt: Int64?

    public init(
        id: CredentialId,
        serviceIdentifier: String,
        username: String,
        label: String,
        createdAt: Int64,
        updatedAt: Int64,
        lastUsedAt: Int64? = nil
    ) {
        self.id = id
        self.serviceIdentifier = serviceIdentifier
        self.username = username
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}

/// Sort orders for the credential list (parity with KeyNest `CredentialSortOrder`,
/// with `packageAsc` renamed to `domainAsc`).
public enum CredentialSortOrder: Sendable, CaseIterable {
    case updatedDesc
    case labelAsc
    case domainAsc
}
