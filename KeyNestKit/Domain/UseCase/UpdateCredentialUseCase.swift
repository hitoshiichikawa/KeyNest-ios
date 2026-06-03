import Foundation

/// Input for [UpdateCredentialUseCase]. Port of KeyNest Android's
/// `UpdateCredentialInput` (`packageName` → `serviceIdentifier`).
///
/// - [newPassword] nil → keep the existing password ciphertext/IV (cheap
///   "edit metadata only"); non-nil → re-encrypt with a fresh IV.
/// - [customFields] nil → keep the existing custom-fields blob; non-nil
///   (including `[]`) → replace it.
public struct UpdateCredentialInput: Sendable {
    public let id: CredentialId
    public let serviceIdentifier: String
    public let username: String
    public let label: String
    public let newPassword: [UInt8]?
    public let customFields: [CustomField]?

    public init(
        id: CredentialId,
        serviceIdentifier: String,
        username: String,
        label: String,
        newPassword: [UInt8]? = nil,
        customFields: [CustomField]? = nil
    ) {
        self.id = id
        self.serviceIdentifier = serviceIdentifier
        self.username = username
        self.label = label
        self.newPassword = newPassword
        self.customFields = customFields
    }
}

/// Failures for [UpdateCredentialUseCase]. Never carries plaintext.
public enum UpdateCredentialError: Error, Equatable {
    case serviceIdentifierBlank
    case usernameBlank
    case labelBlank
    case notFound
}

/// Updates an existing credential. Port of KeyNest Android's
/// `UpdateCredentialUseCase`.
///
/// Password-preservation semantics (the key boundary): when [UpdateCredentialInput.newPassword]
/// is nil, the existing ciphertext/IV are reused so "edit username only" never
/// decrypts or re-encrypts the password.
///
/// Divergence from KeyNest Android (flagged for review): the Android use case
/// rebuilds the record without `lastUsedAt`, which resets it to null on every
/// edit. iOS **preserves** `lastUsedAt` so editing a credential does not drop it
/// from the recently-used carousel.
public struct UpdateCredentialUseCase {
    private let repository: CredentialRepository
    private let cipher: Cipher
    private let customFieldsCodec: EncryptedCustomFieldsCodec
    private let now: () -> Int64

    public init(
        repository: CredentialRepository,
        cipher: Cipher,
        customFieldsCodec: EncryptedCustomFieldsCodec,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.repository = repository
        self.cipher = cipher
        self.customFieldsCodec = customFieldsCodec
        self.now = now
    }

    public func callAsFunction(_ input: UpdateCredentialInput) async throws {
        let serviceIdentifier = input.serviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serviceIdentifier.isEmpty else { throw UpdateCredentialError.serviceIdentifierBlank }
        guard !input.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UpdateCredentialError.usernameBlank
        }
        guard !input.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UpdateCredentialError.labelBlank
        }

        guard let existing = try await repository.findById(input.id) else {
            throw UpdateCredentialError.notFound
        }

        // Re-encrypt the password only when a new one was supplied.
        let passwordCiphertext: Data
        let passwordIv: Data
        if let newPassword = input.newPassword {
            let blob = try cipher.encryptWipingPassword(newPassword)
            passwordCiphertext = blob.ciphertext
            passwordIv = blob.iv
        } else {
            passwordCiphertext = existing.passwordCiphertext
            passwordIv = existing.passwordIv
        }

        // Replace the custom-fields blob only when a new list was supplied.
        let customFieldsCiphertext: Data
        let customFieldsIv: Data
        if let customFields = input.customFields {
            let blob = try customFieldsCodec.encrypt(customFields)
            customFieldsCiphertext = blob.ciphertext
            customFieldsIv = blob.iv
        } else {
            customFieldsCiphertext = existing.customFieldsCiphertext
            customFieldsIv = existing.customFieldsIv
        }

        try await repository.update(
            EncryptedCredentialRecord(
                id: existing.id,
                serviceIdentifier: serviceIdentifier,
                username: input.username,
                label: input.label,
                passwordCiphertext: passwordCiphertext,
                passwordIv: passwordIv,
                createdAt: existing.createdAt,
                updatedAt: now(),
                lastUsedAt: existing.lastUsedAt,  // preserved (see type doc)
                customFieldsCiphertext: customFieldsCiphertext,
                customFieldsIv: customFieldsIv
            )
        )
    }
}
