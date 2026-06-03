import Foundation

/// Short-lived holder for a decrypted credential. Direct port of KeyNest's
/// `PlaintextCredential.kt`.
///
/// The `password` buffer is zero-filled by `close()`, so callers MUST call
/// `close()` in a `defer` (or use `withDecrypted`). `username` / `label` /
/// `serviceIdentifier` are not sensitive on their own and stay as `String`.
///
/// customFields wiping caveat: `String` cannot be deterministically zero-filled
/// on Swift either (immutable, ref-counted), so `close()` only drops the list
/// reference — same accepted limitation as the JVM original.
public final class PlaintextCredential {
    public let id: CredentialId
    public let serviceIdentifier: String
    public let username: String
    public let label: String

    /// Mutable buffer so it can be zero-filled. Treat as the canonical password.
    public private(set) var password: [UInt8]

    private var _customFields: [CustomField]
    public var customFields: [CustomField] { _customFields }

    public private(set) var isClosed: Bool = false

    public init(
        id: CredentialId,
        serviceIdentifier: String,
        username: String,
        label: String,
        password: [UInt8],
        customFields: [CustomField] = []
    ) {
        self.id = id
        self.serviceIdentifier = serviceIdentifier
        self.username = username
        self.label = label
        self.password = password
        self._customFields = customFields
    }

    /// Overwrites the password buffer with zeros and clears custom fields.
    public func close() {
        guard !isClosed else { return }
        for i in password.indices { password[i] = 0 }
        _customFields = []
        isClosed = true
    }

    deinit { close() }

    /// Convenience scope that guarantees `close()` runs after `body`.
    @discardableResult
    public func withDecrypted<R>(_ body: (PlaintextCredential) throws -> R) rethrows -> R {
        defer { close() }
        return try body(self)
    }
}
