import Foundation

/// Round-trips `[CustomField]` through JSON and AES-GCM, reusing the same
/// [Cipher] (and therefore the same data-encryption key) as the credential
/// password. Direct behavioral port of KeyNest Android's
/// `EncryptedCustomFieldsCodec.kt` (Issue #66) — Req 3.4.
///
/// - [encrypt] always produces a **non-empty** [EncryptedBlob], even for an
///   empty list, because the codec serialises `[]` first. Callers therefore
///   always have a deterministic IV + ciphertext pair to persist.
/// - [decrypt] is lenient on two boundaries:
///   - an **empty** `ciphertext` means "no payload" → empty list (rows that
///     have never stored custom fields), not an error.
///   - a **JSON parse failure** is fail-open → empty list + a redacted warning,
///     so a corrupted custom-fields blob never blocks username/password fill
///     (design §Error Handling). The raw JSON is **never** logged — it holds
///     plaintext values.
///
/// A GCM auth-tag failure is deliberately **not** swallowed: [Cipher.decrypt]
/// runs before the JSON `do/catch`, so a `CryptoError.decryptionFailed`
/// propagates to the caller (the unlock use case routes it to its decrypt-error
/// surface), exactly as in the Android original.
public struct EncryptedCustomFieldsCodec {
    private let cipher: Cipher

    public init(cipher: Cipher) {
        self.cipher = cipher
    }

    /// Serialise [customFields] to compact JSON, encrypt, and return the blob.
    /// The intermediate UTF-8 buffer (which holds plaintext values) is zero-filled
    /// before returning, matching the Android `Arrays.fill` wipe (NFR 1.1).
    public func encrypt(_ customFields: [CustomField]) throws -> EncryptedBlob {
        let payload = customFields.map { CustomFieldJson(k: $0.fieldKey, v: $0.value) }
        var bytes = try Self.encoder.encode(payload)
        defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
        return try cipher.encrypt(bytes)
    }

    /// Inverse of [encrypt]. Empty ciphertext → empty list; JSON parse failure →
    /// empty list (fail-open) + redacted warning. The decrypted buffer is
    /// zero-filled before returning (NFR 1.1).
    public func decrypt(_ blob: EncryptedBlob) throws -> [CustomField] {
        if blob.ciphertext.isEmpty {
            return []
        }
        var plaintext = try cipher.decrypt(blob)
        defer { plaintext.resetBytes(in: plaintext.startIndex..<plaintext.endIndex) }
        do {
            let parsed = try Self.decoder.decode([CustomFieldJson].self, from: plaintext)
            return parsed.map { CustomField(fieldKey: $0.k, value: $0.v) }
        } catch {
            // Fail-open: a bad payload must not break password fill. Only the
            // error type is logged (SafeLog), never the JSON (plaintext values).
            SafeLog.warn("customFields JSON parse failed; returning empty list", error: error)
            return []
        }
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

/// Wire-format DTO for [EncryptedCustomFieldsCodec]. Keys are shortened to `k` /
/// `v` to keep the JSON payload (and therefore the AES-GCM ciphertext) compact —
/// byte-format parity with KeyNest Android's `CustomFieldJson.kt`
/// (`@SerialName("k")` / `@SerialName("v")`). Private to the codec; callers only
/// ever see the domain [CustomField].
private struct CustomFieldJson: Codable {
    let k: String
    let v: String
}
