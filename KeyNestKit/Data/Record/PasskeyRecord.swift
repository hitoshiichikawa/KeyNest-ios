import Foundation
import GRDB

/// GRDB persistence row for the `passkeys` table. iOS equivalent of KeyNest
/// Android's `PasskeyEntity`, **without** the per-key `keyAlias` column — iOS
/// encrypts every row with the single shared DEK (確定事項 2).
///
/// [encryptedPrivateKey] / [privateKeyIv] hold the AES-GCM-sealed ES256 private
/// key and its IV; they are projected away by `toDomain()` so they never reach
/// callers (Req 6.4). `credentialId` is the TEXT primary key (base64url WebAuthn
/// id, assigned by the registration ceremony — not autoincremented).
struct PasskeyRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "passkeys"

    var credentialId: String
    var rpId: String
    var rpDisplayName: String?
    var userHandle: Data
    var userName: String?
    var userDisplayName: String?
    var isDiscoverable: Bool
    var encryptedPrivateKey: Data
    var privateKeyIv: Data
    var signCount: Int64
    var displayName: String?
    var createdAt: Int64
    var lastUsedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case credentialId = "credential_id"
        case rpId = "rp_id"
        case rpDisplayName = "rp_display_name"
        case userHandle = "user_handle"
        case userName = "user_name"
        case userDisplayName = "user_display_name"
        case isDiscoverable = "is_discoverable"
        case encryptedPrivateKey = "encrypted_private_key"
        case privateKeyIv = "private_key_iv"
        case signCount = "sign_count"
        case displayName = "display_name"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    enum Columns {
        static let rpId = Column(CodingKeys.rpId)
        static let userHandle = Column(CodingKeys.userHandle)
        static let isDiscoverable = Column(CodingKeys.isDiscoverable)
    }
}
