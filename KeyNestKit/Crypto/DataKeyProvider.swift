import Foundation
import CryptoKit
import Security

/// Errors surfaced by [DataKeyProvider] / [KeychainDataKeyStore]. Opaque on
/// purpose — never carries key bytes (Req 3.5 / NFR 1.1).
public enum DataKeyError: Error, Equatable {
    /// Another writer created the key material between our load and our add
    /// (first-launch race between the app and the extension). Caller re-reads.
    case duplicateItem
    /// A `Security` framework keychain operation returned a non-success status.
    case keychainFailure(OSStatus)
    /// Secure-Enclave sealing of the DEK failed.
    case sealFailed
    /// Secure-Enclave opening of the sealed DEK failed (e.g. tampering, missing key).
    case openFailed
    /// Random DEK / Secure-Enclave key generation failed.
    case keyGenerationFailed
    /// Stored key material was not the expected 32-byte length.
    case invalidKeyData
}

/// Supplies the singleton 256-bit data-encryption key (DEK) used by
/// [AesGcmCipher] to encrypt credential passwords, custom fields and passkey
/// private keys. iOS equivalent of KeyNest Android's `KeystoreKeyProvider`.
///
/// **Why an envelope, not a Keystore-style AES key?** Android stores the AES key
/// inside the Keystore TEE and never extracts it. The iOS Secure Enclave only
/// holds **EC P-256** keys (no AES), so KeyNest mirrors "the raw key never
/// leaves secure hardware" with an *envelope*: a random DEK is sealed (ECIES)
/// under a non-exportable Secure-Enclave P-256 key and only the sealed blob is
/// persisted. The DEK is opened inside the SE on demand and lives only as a
/// short-lived process-memory value (design §Crypto / 確定事項 2).
///
/// On devices without a Secure Enclave the DEK is stored directly in the
/// Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — encryption is
/// **never silently disabled** (Req 3.3).
///
/// Biometric gating is intentionally **not** placed on the key itself: the vault
/// is gated at the app layer by `BiometricAuthenticator` (確定事項 3, parity with
/// KeyNest's app-level `BiometricPrompt`).
///
/// The persistence + Secure-Enclave mechanics are isolated behind
/// [DataKeyStore] so the unlock/rotate logic here is unit-testable without an
/// entitled host app (parity with KeyNest making `KeystoreKeyProvider` `open`
/// for test substitution). The real backend is [KeychainDataKeyStore].
public protocol DataKeyProviding: AnyObject {
    /// Returns the DEK, creating + persisting it on first use. Cached in memory
    /// for the process lifetime so the AutoFill candidate path stays fast
    /// (NFR 2.1).
    func dataKey() throws -> SymmetricKey

    /// Removes the persisted key material (sealed DEK + Secure-Enclave key) and
    /// drops the in-memory cache. Used by the Danger Zone "clear vault" flow
    /// (Req 7.4 / parity with `KeystoreKeyProvider.deleteKey`).
    func clearAll() throws
}

public final class DataKeyProvider: DataKeyProviding {
    private static let dataKeyByteCount = 32  // AES-256

    private let store: DataKeyStore
    private let randomBytes: (Int) throws -> Data

    private let lock = NSLock()
    private var cached: SymmetricKey?

    /// Production initializer: backs onto the shared Keychain + Secure Enclave.
    /// On Simulator builds the shared access group is unavailable without
    /// signing; we fall back to the app-local Keychain so the SwiftUI shell
    /// can boot for smoke-testing (extension parity is lost — Sim only).
    public convenience init(
        accessGroup: String? = DataKeyProvider.defaultAccessGroup,
        forceFallback: Bool = false
    ) {
        self.init(store: KeychainDataKeyStore(accessGroup: accessGroup, forceFallback: forceFallback))
    }

    public static var defaultAccessGroup: String? {
        #if targetEnvironment(simulator)
        return nil
        #else
        return AppGroup.keychainAccessGroup
        #endif
    }

    /// Test seam: inject a fake [DataKeyStore] and/or a deterministic byte
    /// generator. Internal so `@testable import KeyNestKit` can reach it.
    init(store: DataKeyStore, randomBytes: @escaping (Int) throws -> Data = DataKeyProvider.secureRandomBytes) {
        self.store = store
        self.randomBytes = randomBytes
    }

    public func dataKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let key = try loadOrCreate()
        cached = key
        return key
    }

    public func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        try store.deleteSealedDataKey()
        try store.deleteSealingKey()
    }

    // MARK: - Load / create

    private func loadOrCreate() throws -> SymmetricKey {
        if let blob = try store.loadSealedDataKey() {
            return try decode(blob)
        }
        // First launch on this device: mint a fresh DEK.
        var raw = try randomBytes(Self.dataKeyByteCount)
        defer { raw.resetBytes(in: raw.startIndex..<raw.endIndex) }
        guard raw.count == Self.dataKeyByteCount else { throw DataKeyError.invalidKeyData }

        let blob = store.sealsKeyMaterial ? try store.seal(raw) : raw
        do {
            try store.addSealedDataKey(blob)
        } catch DataKeyError.duplicateItem {
            // Lost the first-launch race (the other process created it first).
            // Adopt the persisted key instead of clobbering it — otherwise we
            // would orphan whatever the other process already encrypted.
            guard let existing = try store.loadSealedDataKey() else {
                throw DataKeyError.keychainFailure(errSecItemNotFound)
            }
            return try decode(existing)
        }
        return SymmetricKey(data: raw)
    }

    private func decode(_ blob: Data) throws -> SymmetricKey {
        var raw = store.sealsKeyMaterial ? try store.open(blob) : blob
        defer { raw.resetBytes(in: raw.startIndex..<raw.endIndex) }
        guard raw.count == Self.dataKeyByteCount else { throw DataKeyError.invalidKeyData }
        return SymmetricKey(data: raw)
    }

    // MARK: - CSPRNG

    static func secureRandomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw DataKeyError.keyGenerationFailed }
        return Data(bytes)
    }
}

// MARK: - DataKeyStore seam

/// Backend that persists the (sealed-or-raw) DEK material and performs
/// Secure-Enclave sealing when available. Isolated from [DataKeyProvider] so the
/// key lifecycle is unit-testable with an in-memory fake.
protocol DataKeyStore {
    /// `true` when [seal] / [open] are exercised (a Secure Enclave is present
    /// and not force-disabled). `false` selects the raw-Keychain fallback
    /// (Req 3.3).
    var sealsKeyMaterial: Bool { get }

    /// Returns the persisted key material (sealed blob, or raw DEK in fallback),
    /// or `nil` on first launch.
    func loadSealedDataKey() throws -> Data?

    /// Persists the key material. **Add-only**: throws [DataKeyError.duplicateItem]
    /// when an item already exists, so a first-launch race can never overwrite a
    /// key already in use.
    func addSealedDataKey(_ blob: Data) throws

    /// Removes the persisted key material. No-op when absent.
    func deleteSealedDataKey() throws

    /// Seals raw DEK bytes under the Secure-Enclave key (creating it on first
    /// use). Only called when [sealsKeyMaterial] is `true`.
    func seal(_ rawKey: Data) throws -> Data

    /// Opens a sealed blob back to raw DEK bytes inside the Secure Enclave.
    func open(_ sealed: Data) throws -> Data

    /// Removes the Secure-Enclave key. No-op when absent (fallback devices).
    func deleteSealingKey() throws
}

// MARK: - Keychain + Secure Enclave backend

/// `Security`-framework implementation of [DataKeyStore].
///
/// - Sealed/raw DEK → a `kSecClassGenericPassword` item in the shared Keychain
///   access group, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
///   `synchronizable = false` (NFR 1.3: never iCloud-synced).
/// - Secure-Enclave KEK → a `kSecClassKey` EC P-256 token key
///   (`kSecAttrTokenIDSecureEnclave`) in the same access group, access control
///   `[.privateKeyUsage]` with no biometric flag (app-layer gate, 確定事項 3).
/// - ECIES algorithm: `eciesEncryptionStandardX963SHA256AESGCM`.
///
/// `kSecUseDataProtectionKeychain = true` is set on every query so access-group
/// sharing between the app and the extension uses the modern data-protection
/// keychain consistently.
///
/// > Verify on a device: Secure-Enclave key creation and ECIES seal/open run
/// > only on real hardware (the simulator reports `SecureEnclave.isAvailable ==
/// > false`, exercising the fallback path). Keychain access-group queries need
/// > the two targets' entitlements wired, so end-to-end verification happens on
/// > Mac/device, mirroring KeyNest's instrumented `KeystoreKeyProviderTest`.
final class KeychainDataKeyStore: DataKeyStore {
    private static let ecies: SecKeyAlgorithm = .eciesEncryptionStandardX963SHA256AESGCM

    private let accessGroup: String?
    private let kekTag: Data
    private let dekAccount: String
    private let dekService: String

    let sealsKeyMaterial: Bool

    init(
        accessGroup: String?,
        forceFallback: Bool,
        kekTag: Data = Data("io.github.hitoshiichikawa.ios.keynest.kek.v1".utf8),
        dekAccount: String = "keynest.dek.v1",
        dekService: String = "io.github.hitoshiichikawa.ios.keynest.datakey"
    ) {
        self.accessGroup = accessGroup
        self.kekTag = kekTag
        self.dekAccount = dekAccount
        self.dekService = dekService
        self.sealsKeyMaterial = !forceFallback && SecureEnclave.isAvailable
    }

    // MARK: DEK blob (generic password)

    private func blobIdentityQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: dekAccount,
            kSecAttrService as String: dekService,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    func loadSealedDataKey() throws -> Data? {
        var query = blobIdentityQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess: return out as? Data
        case errSecItemNotFound: return nil
        default: throw DataKeyError.keychainFailure(status)
        }
    }

    func addSealedDataKey(_ blob: Data) throws {
        var attributes = blobIdentityQuery()
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        attributes[kSecValueData as String] = blob
        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem: throw DataKeyError.duplicateItem
        default: throw DataKeyError.keychainFailure(status)
        }
    }

    func deleteSealedDataKey() throws {
        let status = SecItemDelete(blobIdentityQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DataKeyError.keychainFailure(status)
        }
    }

    // MARK: Secure-Enclave KEK

    private func seKeyIdentityQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String: kekTag,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    private func loadSecureEnclaveKey() throws -> SecKey? {
        var query = seKeyIdentityQuery()
        query[kSecReturnRef as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            // SecItemCopyMatching with kSecReturnRef on a key class returns a SecKey.
            return (out as! SecKey)  // swiftlint:disable:this force_cast
        case errSecItemNotFound:
            return nil
        default:
            throw DataKeyError.keychainFailure(status)
        }
    }

    private func createSecureEnclaveKey() throws -> SecKey {
        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &acError
        ) else {
            throw DataKeyError.keyGenerationFailed
        }
        var privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: kekTag,
            kSecAttrAccessControl as String: access,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { privateAttrs[kSecAttrAccessGroup as String] = accessGroup }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: privateAttrs,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw DataKeyError.keyGenerationFailed
        }
        return key
    }

    private func secureEnclaveKey() throws -> SecKey {
        if let existing = try loadSecureEnclaveKey() { return existing }
        return try createSecureEnclaveKey()
    }

    func seal(_ rawKey: Data) throws -> Data {
        let privateKey = try secureEnclaveKey()
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              SecKeyIsAlgorithmSupported(publicKey, .encrypt, Self.ecies) else {
            throw DataKeyError.sealFailed
        }
        var error: Unmanaged<CFError>?
        guard let sealed = SecKeyCreateEncryptedData(publicKey, Self.ecies, rawKey as CFData, &error) else {
            throw DataKeyError.sealFailed
        }
        return sealed as Data
    }

    func open(_ sealed: Data) throws -> Data {
        guard let privateKey = try loadSecureEnclaveKey(),
              SecKeyIsAlgorithmSupported(privateKey, .decrypt, Self.ecies) else {
            throw DataKeyError.openFailed
        }
        var error: Unmanaged<CFError>?
        guard let plaintext = SecKeyCreateDecryptedData(privateKey, Self.ecies, sealed as CFData, &error) else {
            throw DataKeyError.openFailed
        }
        return plaintext as Data
    }

    func deleteSealingKey() throws {
        let status = SecItemDelete(seKeyIdentityQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DataKeyError.keychainFailure(status)
        }
    }
}
