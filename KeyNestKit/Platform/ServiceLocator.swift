import Foundation

/// Hand-rolled dependency container shared by the app and the AutoFill
/// extension. iOS equivalent of KeyNest Android's `ServiceLocator` (no Hilt / DI
/// framework — design Technology Stack).
///
/// Wires the crypto + data layer (database, data key, cipher, custom-fields
/// codec, repositories), the biometric authenticator, the storage measurer, and
/// the domain use cases. Later phases extend it with the AutoFill identity-store
/// sync and the UI composition.
public final class ServiceLocator {
    // Infrastructure
    public let database: AppDatabase
    public let dataKeyProvider: DataKeyProviding
    public let cipher: Cipher
    public let customFieldsCodec: EncryptedCustomFieldsCodec
    public let credentialRepository: CredentialRepository
    public let passkeyRepository: PasskeyRepository
    public let biometricAuthenticator: BiometricAuthenticating
    public let vaultStorageMeasurer: VaultStorageMeasuring
    public let identityStoreSync: CredentialIdentityStoreSyncing

    // WebAuthn (Phase 2.5) — registration byte builder. Assertion signing is the
    // stateless `PasskeyAssertion` enum, used directly by the Phase 5 coordinator.
    public let passkeyCreator: PasskeyCreator

    // Use cases (Phase 2.2)
    public let saveCredential: SaveCredentialUseCase
    public let updateCredential: UpdateCredentialUseCase
    public let unlockVault: UnlockVaultUseCase
    public let deleteCredential: DeleteCredentialUseCase
    public let duplicateCredential: DuplicateCredentialUseCase
    public let markCredentialUsed: MarkCredentialUsedUseCase
    public let listCredentials: ListCredentialsUseCase
    public let observeRecentlyUsed: ObserveRecentlyUsedUseCase
    public let observeVaultMetadata: ObserveVaultMetadataUseCase
    public let listPasskeys: ListPasskeysUseCase
    public let clearVault: ClearVaultUseCase
    public let getVaultStorageUsage: GetVaultStorageUsageUseCase
    public let getDeviceLockStatus: GetDeviceLockStatusUseCase

    public init(
        database: AppDatabase,
        dataKeyProvider: DataKeyProviding,
        biometricAuthenticator: BiometricAuthenticating = BiometricAuthenticator(),
        vaultStorageMeasurer: VaultStorageMeasuring = VaultStorageMeasurer(),
        passkeyCreator: PasskeyCreator = PasskeyCreator(),
        identityStoreSync: CredentialIdentityStoreSyncing = CredentialIdentityStoreSync()
    ) {
        self.database = database
        self.dataKeyProvider = dataKeyProvider
        self.biometricAuthenticator = biometricAuthenticator
        self.vaultStorageMeasurer = vaultStorageMeasurer
        self.passkeyCreator = passkeyCreator
        self.identityStoreSync = identityStoreSync

        // One DEK-backed cipher shared by passwords, custom fields and passkeys.
        let cipher = AesGcmCipher(keyProvider: { try dataKeyProvider.dataKey() })
        let codec = EncryptedCustomFieldsCodec(cipher: cipher)
        let credentialRepository = CredentialRepositoryImpl(database: database)
        let passkeyRepository = PasskeyRepositoryImpl(database: database, cipher: cipher)
        self.cipher = cipher
        self.customFieldsCodec = codec
        self.credentialRepository = credentialRepository
        self.passkeyRepository = passkeyRepository

        self.saveCredential = SaveCredentialUseCase(
            repository: credentialRepository, cipher: cipher, customFieldsCodec: codec
        )
        self.updateCredential = UpdateCredentialUseCase(
            repository: credentialRepository, cipher: cipher, customFieldsCodec: codec
        )
        self.unlockVault = UnlockVaultUseCase(
            repository: credentialRepository, cipher: cipher, customFieldsCodec: codec
        )
        self.deleteCredential = DeleteCredentialUseCase(repository: credentialRepository)
        self.duplicateCredential = DuplicateCredentialUseCase(repository: credentialRepository)
        self.markCredentialUsed = MarkCredentialUsedUseCase(repository: credentialRepository)
        self.listCredentials = ListCredentialsUseCase(repository: credentialRepository)
        self.observeRecentlyUsed = ObserveRecentlyUsedUseCase(repository: credentialRepository)
        self.observeVaultMetadata = ObserveVaultMetadataUseCase(repository: credentialRepository)
        self.listPasskeys = ListPasskeysUseCase(repository: passkeyRepository)
        self.clearVault = ClearVaultUseCase(
            credentialRepository: credentialRepository,
            passkeyRepository: passkeyRepository,
            dataKeyProvider: dataKeyProvider
        )
        self.getVaultStorageUsage = GetVaultStorageUsageUseCase(measurer: vaultStorageMeasurer)
        self.getDeviceLockStatus = GetDeviceLockStatusUseCase(authenticator: biometricAuthenticator)
    }

    /// Builds the production container backed by the shared App Group database
    /// and the Keychain/Secure-Enclave data key.
    public static func makeShared() throws -> ServiceLocator {
        ServiceLocator(
            database: try AppDatabase.makeShared(),
            dataKeyProvider: DataKeyProvider()
        )
    }
}
