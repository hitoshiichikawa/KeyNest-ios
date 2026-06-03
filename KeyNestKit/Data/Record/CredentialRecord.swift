import Foundation
import GRDB

/// GRDB persistence row for the `credentials` table. iOS equivalent of KeyNest
/// Android's `CredentialEntity`, with `package_name` → `service_identifier` and
/// the signature columns dropped.
///
/// The plaintext password is never stored — only [passwordCiphertext] /
/// [passwordIv] (and the custom-fields blobs) are persisted. `CodingKeys` map
/// the camelCase properties onto the snake_case columns declared in
/// `AppDatabase`'s `v1` migration.
struct CredentialRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "credentials"

    /// nil for a not-yet-inserted row (SQLite assigns the autoincrement id).
    var id: Int64?
    var serviceIdentifier: String
    var username: String
    var label: String
    var passwordCiphertext: Data
    var passwordIv: Data
    var customFieldsCiphertext: Data
    var customFieldsIv: Data
    var createdAt: Int64
    var updatedAt: Int64
    var lastUsedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case serviceIdentifier = "service_identifier"
        case username
        case label
        case passwordCiphertext = "password_ciphertext"
        case passwordIv = "password_iv"
        case customFieldsCiphertext = "custom_fields_ciphertext"
        case customFieldsIv = "custom_fields_iv"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastUsedAt = "last_used_at"
    }

    enum Columns {
        static let serviceIdentifier = Column(CodingKeys.serviceIdentifier)
    }

    /// Capture the assigned rowid after insert.
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
