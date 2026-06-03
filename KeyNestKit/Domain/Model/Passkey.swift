import Foundation

/// Domain aggregate for a stored PassKey, as seen *outside* the persistence
/// boundary. Port of KeyNest Android's `Passkey`.
///
/// Why a separate type from the GRDB record: the persistence row
/// (`PasskeyRecord`) carries the AES-GCM-encrypted private key + its IV. Those
/// are persistence internals and MUST NOT cross the repository boundary (Req 6.4
/// / NFR — secret material stays in the data layer). To read the decrypted
/// private key, callers go through `PasskeyRepository.loadPrivateKey`; the bytes
/// are never carried on a `Passkey`.
///
/// Unlike the Kotlin original (a hand-written class to get `ByteArray` content
/// equality), this is a `struct`: `Data` already has value semantics and
/// content-based `Equatable`, so the synthesized conformances are correct.
public struct Passkey: Sendable, Equatable {
    public let credentialId: String
    public let rpId: String
    public let rpDisplayName: String?
    public let userHandle: Data
    public let userName: String?
    public let userDisplayName: String?
    public let isDiscoverable: Bool
    public let signCount: Int64
    public let displayName: String?
    public let createdAt: Int64
    public let lastUsedAt: Int64?

    public init(
        credentialId: String,
        rpId: String,
        rpDisplayName: String?,
        userHandle: Data,
        userName: String?,
        userDisplayName: String?,
        isDiscoverable: Bool,
        signCount: Int64,
        displayName: String?,
        createdAt: Int64,
        lastUsedAt: Int64?
    ) {
        self.credentialId = credentialId
        self.rpId = rpId
        self.rpDisplayName = rpDisplayName
        self.userHandle = userHandle
        self.userName = userName
        self.userDisplayName = userDisplayName
        self.isDiscoverable = isDiscoverable
        self.signCount = signCount
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

extension Passkey: CustomStringConvertible {
    /// Redacts the opaque `userHandle` to a size marker (W3C WebAuthn §5.4.3
    /// forbids exposing it; parity with the Android `toString`).
    public var description: String {
        "Passkey(credentialId=\(credentialId), rpId=\(rpId), rpDisplayName=\(rpDisplayName ?? "nil"), "
            + "userHandle=<\(userHandle.count)B>, userName=\(userName ?? "nil"), "
            + "userDisplayName=\(userDisplayName ?? "nil"), isDiscoverable=\(isDiscoverable), "
            + "signCount=\(signCount), displayName=\(displayName ?? "nil"), "
            + "createdAt=\(createdAt), lastUsedAt=\(lastUsedAt.map { String($0) } ?? "nil"))"
    }
}
