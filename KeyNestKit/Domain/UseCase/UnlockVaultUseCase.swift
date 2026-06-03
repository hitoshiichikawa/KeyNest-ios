import Foundation

/// Failures for [UnlockVaultUseCase]. Never carries decrypted bytes.
public enum UnlockError: Error, Equatable {
    case notFound
    case decryptFailed
}

/// Decrypts a credential and returns it wrapped in a [PlaintextCredential]
/// (which zero-fills its password buffer on `close()`). Port of KeyNest
/// Android's `UnlockVaultUseCase`.
///
/// The password decrypt failure fails the unlock ([UnlockError.decryptFailed]).
/// A custom-fields decrypt failure (AEAD or JSON) is **fail-open**: the user has
/// already authenticated and the password decrypted fine, so a corrupt
/// custom-fields blob yields an empty list (with a redacted warning) rather than
/// blocking the unlock — parity with KeyNest's `decryptCustomFields`.
public struct UnlockVaultUseCase {
    private let repository: CredentialRepository
    private let cipher: Cipher
    private let customFieldsCodec: EncryptedCustomFieldsCodec

    public init(
        repository: CredentialRepository,
        cipher: Cipher,
        customFieldsCodec: EncryptedCustomFieldsCodec
    ) {
        self.repository = repository
        self.cipher = cipher
        self.customFieldsCodec = customFieldsCodec
    }

    public func callAsFunction(_ id: CredentialId) async throws -> PlaintextCredential {
        guard let record = try await repository.findById(id) else {
            throw UnlockError.notFound
        }

        var passwordData: Data
        do {
            passwordData = try cipher.decrypt(
                EncryptedBlob(iv: record.passwordIv, ciphertext: record.passwordCiphertext)
            )
        } catch {
            throw UnlockError.decryptFailed
        }
        defer { passwordData.resetBytes(in: passwordData.startIndex..<passwordData.endIndex) }

        let customFields = decryptCustomFields(record)

        return PlaintextCredential(
            id: record.id,
            serviceIdentifier: record.serviceIdentifier,
            username: record.username,
            label: record.label,
            password: [UInt8](passwordData),
            customFields: customFields
        )
    }

    /// Decrypts the custom-fields blob, failing open to an empty list on any
    /// error (AEAD mismatch or JSON corruption) so a damaged blob never blocks
    /// password fill. Empty ciphertext → empty list without touching the cipher.
    private func decryptCustomFields(_ record: EncryptedCredentialRecord) -> [CustomField] {
        do {
            return try customFieldsCodec.decrypt(
                EncryptedBlob(iv: record.customFieldsIv, ciphertext: record.customFieldsCiphertext)
            )
        } catch {
            SafeLog.warn("customFields decrypt failed; returning empty list", error: error)
            return []
        }
    }
}
