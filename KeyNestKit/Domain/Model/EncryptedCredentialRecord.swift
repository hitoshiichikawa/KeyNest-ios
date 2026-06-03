import Foundation

/// A credential plus its encrypted password / custom-fields blobs. Used at the
/// repository boundary (data ⇄ domain). Direct port of KeyNest Android's
/// `EncryptedCredentialRecord`, with the iOS differences:
/// - `packageName` → `serviceIdentifier` (normalized web domain).
/// - `signatureSha256` / `signatureCapturedAt` removed (no per-app signing
///   match on iOS).
///
/// The plaintext password is never carried here — it is reconstructed only on
/// the short-lived `PlaintextCredential` after an explicit unlock + decrypt.
///
/// > On `save`, the repository ignores [id] (a new row id is assigned by
/// > SQLite). Callers building a brand-new record pass a sentinel `CredentialId(0)`.
public struct EncryptedCredentialRecord: Sendable, Equatable {
    public let id: CredentialId
    /// Normalized target domain, e.g. "example.com".
    public let serviceIdentifier: String
    public let username: String
    public let label: String
    /// AES-GCM ciphertext ‖ tag of the password.
    public let passwordCiphertext: Data
    /// 12-byte GCM IV for [passwordCiphertext].
    public let passwordIv: Data
    public let createdAt: Int64
    public let updatedAt: Int64
    /// Epoch millis of the most recent autofill consumption; nil = never used.
    public let lastUsedAt: Int64?
    /// AES-GCM ciphertext of the JSON-encoded custom-fields list. Empty Data
    /// means "no custom fields" (codec treats empty BLOB as an empty list).
    public let customFieldsCiphertext: Data
    /// 12-byte GCM IV for [customFieldsCiphertext]; empty when that is empty.
    public let customFieldsIv: Data

    public init(
        id: CredentialId,
        serviceIdentifier: String,
        username: String,
        label: String,
        passwordCiphertext: Data,
        passwordIv: Data,
        createdAt: Int64,
        updatedAt: Int64,
        lastUsedAt: Int64? = nil,
        customFieldsCiphertext: Data = Data(),
        customFieldsIv: Data = Data()
    ) {
        self.id = id
        self.serviceIdentifier = serviceIdentifier
        self.username = username
        self.label = label
        self.passwordCiphertext = passwordCiphertext
        self.passwordIv = passwordIv
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.customFieldsCiphertext = customFieldsCiphertext
        self.customFieldsIv = customFieldsIv
    }
}

extension EncryptedCredentialRecord: CustomStringConvertible {
    /// Redacts the encrypted byte blobs to size markers (parity with the Android
    /// `toString` redaction, NFR 1.1). Non-secret metadata stays visible.
    public var description: String {
        "EncryptedCredentialRecord(id=\(id.value), serviceIdentifier=\(serviceIdentifier), "
            + "username=\(username), label=\(label), "
            + "ciphertext=<\(passwordCiphertext.count)B>, iv=<\(passwordIv.count)B>, "
            + "createdAt=\(createdAt), updatedAt=\(updatedAt), lastUsedAt=\(lastUsedAt.map { String($0) } ?? "nil"), "
            + "customFieldsCiphertext=<\(customFieldsCiphertext.count)B>, customFieldsIv=<\(customFieldsIv.count)B>)"
    }
}
