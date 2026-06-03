import Foundation

/// Failures for [ClearVaultUseCase]. Never carries plaintext.
public enum ClearVaultError: Error, Equatable {
    /// Deleting the credential or passkey rows failed.
    case storage
    /// Deleting the data-encryption key material failed.
    case keyMaterial
}

/// Atomically empties the vault for the Danger Zone "clear vault" flow:
/// deletes all credentials, all passkeys, and the data-encryption key material
/// (Req 7.4). Port of KeyNest Android's `ClearVaultUseCase`, adapted to iOS:
/// - also clears the `passkeys` table (Android's version predated passkeys);
/// - drops the single DEK via [DataKeyProviding.clearAll] (no per-key alias);
/// - the Android `detected_fields` table is a Non-Goal on iOS, so it is absent.
///
/// Processing order is **DB-first, then key**: deleting rows before the key
/// avoids the state where ciphertext rows exist but the key is gone (which would
/// surface as "credentials I can't open"). No plaintext is materialised (rows
/// are deleted column-wise by SQLite).
public struct ClearVaultUseCase {
    private let credentialRepository: CredentialRepository
    private let passkeyRepository: PasskeyRepository
    private let dataKeyProvider: DataKeyProviding

    public init(
        credentialRepository: CredentialRepository,
        passkeyRepository: PasskeyRepository,
        dataKeyProvider: DataKeyProviding
    ) {
        self.credentialRepository = credentialRepository
        self.passkeyRepository = passkeyRepository
        self.dataKeyProvider = dataKeyProvider
    }

    public func callAsFunction() async throws {
        do {
            try await credentialRepository.clearAll()
            try await passkeyRepository.clearAll()
        } catch {
            throw ClearVaultError.storage
        }
        do {
            try dataKeyProvider.clearAll()
        } catch {
            throw ClearVaultError.keyMaterial
        }
    }
}
