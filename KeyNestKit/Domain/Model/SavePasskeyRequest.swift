import Foundation

/// Request DTO carrying the plaintext PassKey material from the registration
/// ceremony into the repository boundary, where the private key is AES-GCM
/// encrypted (with the shared DEK) before INSERT. Port of KeyNest Android's
/// `SavePasskeyRequest`, minus the per-key `keyAlias` (iOS unifies on a single
/// DEK + Secure-Enclave envelope — 確定事項 2).
///
/// Mutability / wipe contract: [privateKey] is plaintext key material. The
/// repository encrypts it but does **not** wipe the caller's copy; the
/// registration flow (Phase 2.5 `PasskeyCreator`) zero-fills it after `save`
/// returns (NFR 1.1).
public struct SavePasskeyRequest: Sendable, Equatable {
    public let credentialId: String
    public let rpId: String
    public let rpDisplayName: String?
    public let userHandle: Data
    public let userName: String?
    public let userDisplayName: String?
    public let isDiscoverable: Bool
    /// Plaintext private-key bytes (representation chosen by `PasskeyCreator`).
    /// The repository AES-GCM encrypts this before persisting. Declared `var`
    /// so the caller can `resetBytes` after `save` returns (NFR 1.1 wipe — the
    /// repository does not wipe the caller's buffer).
    public var privateKey: Data
    public let signCount: Int64
    public let displayName: String?
    public let createdAt: Int64

    public init(
        credentialId: String,
        rpId: String,
        rpDisplayName: String?,
        userHandle: Data,
        userName: String?,
        userDisplayName: String?,
        isDiscoverable: Bool,
        privateKey: Data,
        signCount: Int64,
        displayName: String?,
        createdAt: Int64
    ) {
        self.credentialId = credentialId
        self.rpId = rpId
        self.rpDisplayName = rpDisplayName
        self.userHandle = userHandle
        self.userName = userName
        self.userDisplayName = userDisplayName
        self.isDiscoverable = isDiscoverable
        self.privateKey = privateKey
        self.signCount = signCount
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

extension SavePasskeyRequest: CustomStringConvertible {
    /// Redacts the opaque `userHandle` and the secret `privateKey` to size
    /// markers (NFR 1.1 — never log key material).
    public var description: String {
        "SavePasskeyRequest(credentialId=\(credentialId), rpId=\(rpId), "
            + "rpDisplayName=\(rpDisplayName ?? "nil"), userHandle=<\(userHandle.count)B>, "
            + "userName=\(userName ?? "nil"), userDisplayName=\(userDisplayName ?? "nil"), "
            + "isDiscoverable=\(isDiscoverable), privateKey=<\(privateKey.count)B>, "
            + "signCount=\(signCount), displayName=\(displayName ?? "nil"), createdAt=\(createdAt))"
    }
}
