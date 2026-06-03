import Foundation

/// Input for [SaveCredentialUseCase]. Port of KeyNest Android's
/// `NewCredentialInput`, with `packageName` → `serviceIdentifier`.
///
/// [password] is the UTF-8 byte form of the password. iOS value semantics and
/// `String` immutability mean the caller's copy cannot be deterministically
/// wiped (same accepted limitation noted on `PlaintextCredential`); the use case
/// minimises its own footprint by zero-filling the working buffer after
/// encryption.
public struct NewCredentialInput: Sendable {
    public let serviceIdentifier: String
    public let username: String
    public let password: [UInt8]
    public let label: String
    public let customFields: [CustomField]

    public init(
        serviceIdentifier: String,
        username: String,
        password: [UInt8],
        label: String,
        customFields: [CustomField] = []
    ) {
        self.serviceIdentifier = serviceIdentifier
        self.username = username
        self.password = password
        self.label = label
        self.customFields = customFields
    }
}

/// Validation failures for [SaveCredentialUseCase]. Never carries plaintext.
/// (Domain-format validation of `serviceIdentifier` is the edit screen's job via
/// `ServiceIdentifierMatcher` in Phase 4; this use case only blank-checks.)
public enum SaveCredentialError: Error, Equatable {
    case serviceIdentifierBlank
    case usernameBlank
    case passwordBlank
    case labelBlank
}

/// Persists a new credential: validate → encrypt password (fresh IV) → encrypt
/// custom fields → insert. Port of KeyNest Android's `SaveCredentialUseCase`,
/// minus the Android package-signature resolution (no per-app signing match on
/// iOS).
public struct SaveCredentialUseCase {
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

    @discardableResult
    public func callAsFunction(_ input: NewCredentialInput) async throws -> CredentialId {
        try validate(input)

        // Encrypt the password (the working buffer is zero-filled before the
        // ciphertext is persisted — parity with KeyNest's wipe-before-save).
        let passwordBlob = try cipher.encryptWipingPassword(input.password)

        // Always encrypt the custom fields ([] serialises to a non-empty blob)
        // so the persistence shape stays uniform.
        let customFieldsBlob = try customFieldsCodec.encrypt(input.customFields)

        let timestamp = now()
        return try await repository.save(
            EncryptedCredentialRecord(
                id: CredentialId(0),
                serviceIdentifier: input.serviceIdentifier,
                username: input.username,
                label: input.label,
                passwordCiphertext: passwordBlob.ciphertext,
                passwordIv: passwordBlob.iv,
                createdAt: timestamp,
                updatedAt: timestamp,
                lastUsedAt: nil,
                customFieldsCiphertext: customFieldsBlob.ciphertext,
                customFieldsIv: customFieldsBlob.iv
            )
        )
    }

    private func validate(_ input: NewCredentialInput) throws {
        if input.serviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SaveCredentialError.serviceIdentifierBlank
        }
        if input.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SaveCredentialError.usernameBlank
        }
        if input.password.isEmpty {
            throw SaveCredentialError.passwordBlank
        }
        if input.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SaveCredentialError.labelBlank
        }
    }
}
