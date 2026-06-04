import Foundation
import CryptoKit

/// Input for [PasskeyCreator.create]. Port of KeyNest Android's
/// `PasskeyCreateInput`.
public struct PasskeyCreateInput: Sendable {
    public let rpId: String
    public let rpDisplayName: String?
    public let userHandle: Data
    public let userName: String?
    public let userDisplayName: String?
    public let isDiscoverable: Bool

    public init(
        rpId: String,
        rpDisplayName: String?,
        userHandle: Data,
        userName: String?,
        userDisplayName: String?,
        isDiscoverable: Bool
    ) {
        self.rpId = rpId
        self.rpDisplayName = rpDisplayName
        self.userHandle = userHandle
        self.userName = userName
        self.userDisplayName = userDisplayName
        self.isDiscoverable = isDiscoverable
    }
}

/// Output of [PasskeyCreator.create]. Port of KeyNest Android's
/// `PasskeyCreateResult`, minus `registrationResponseJson` (iOS returns an
/// `ASPasskeyRegistrationCredential` built from [attestationObject] + the OS
/// `clientDataHash`, not a WebAuthn JSON string — that wiring is the Phase 5
/// extension coordinator's job).
///
/// [savePasskeyRequest] carries the **plaintext** P-256 private key
/// (`rawRepresentation`); the caller persists it via `PasskeyRepository.save`,
/// which AES-GCM encrypts it with the shared DEK (Req 6.4).
public struct PasskeyCreateResult: Sendable {
    public let credentialId: String
    public let credentialIdBytes: Data
    public let publicKeyCose: Data
    public let authenticatorData: Data
    public let attestationObject: Data
    public let savePasskeyRequest: SavePasskeyRequest
}

/// Failures raised by [PasskeyCreator.create].
public enum PasskeyCreationError: Error, Equatable {
    case encoding
}

/// Core of the PassKey registration ceremony (Req 6.1 / 6.2). Port of KeyNest
/// Android's `PasskeyCreator`, with the iOS substitutions from design §PassKey:
/// - key generation uses **CryptoKit `P256.Signing.PrivateKey`** (no JCE);
/// - the COSE_Key is built from `publicKey.rawRepresentation` (64-byte x‖y);
/// - **no per-key Keystore alias / wrapping key** — encryption at rest is the
///   single shared DEK applied by `PasskeyRepository.save` (確定事項 2);
/// - the AAGUID is the iOS-minted value in `KeynestAaguid`.
///
/// Pure byte-builder: no network, no DB, no Keychain. It returns the WebAuthn
/// bytes plus a [SavePasskeyRequest] the caller persists (and whose private-key
/// buffer the caller wipes after `save` returns — NFR 1.1).
///
/// Test seams: [makeCredentialIdBytes] and [makePrivateKey] are injectable so
/// byte-layout tests can pin a deterministic credential id and key.
public struct PasskeyCreator {
    public static let credentialIdByteCount = 32
    private static let initialSignCount: Int64 = 0

    private let makeCredentialIdBytes: () -> Data
    private let makePrivateKey: () -> P256.Signing.PrivateKey
    private let now: () -> Int64

    public init(
        makeCredentialIdBytes: @escaping () -> Data = { PasskeyCreator.randomCredentialId() },
        makePrivateKey: @escaping () -> P256.Signing.PrivateKey = { P256.Signing.PrivateKey() },
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.makeCredentialIdBytes = makeCredentialIdBytes
        self.makePrivateKey = makePrivateKey
        self.now = now
    }

    public func create(_ input: PasskeyCreateInput) throws -> PasskeyCreateResult {
        let credentialIdBytes = makeCredentialIdBytes()
        let credentialId = Base64URL.encode(credentialIdBytes)
        let privateKey = makePrivateKey()
        let publicKey = privateKey.publicKey

        let publicKeyCose: Data
        do {
            // rawRepresentation is the 64-byte uncompressed x‖y for P-256.
            publicKeyCose = try CoseKeyEncoder.encodeEs256(rawXY: publicKey.rawRepresentation)
        } catch {
            throw PasskeyCreationError.encoding
        }

        let rpIdHash = AuthenticatorDataBuilder.rpIdHash(input.rpId)
        // WebAuthn L3 §6.5.4: when fmt="none" the AAGUID MUST be 16 zero bytes
        // (privacy requirement — a real AAGUID would identify the authenticator
        // model to the RP, defeating the purpose of "none" attestation). iOS
        // WebKit enforces this; sending a non-zero AAGUID with fmt="none"
        // makes Safari surface NotAllowedError to the RP.
        let attestedCredentialData = AuthenticatorDataBuilder.attestedCredentialData(
            aaguid: Data(repeating: 0, count: 16),
            credentialId: credentialIdBytes,
            publicKeyCose: publicKeyCose
        )
        let authenticatorData = AuthenticatorDataBuilder.build(
            rpIdHash: rpIdHash,
            flags: AuthenticatorDataBuilder.flagsRegistration,  // 0x5D = UP|UV|BE|BS|AT
            signCount: 0,
            attestedCredentialData: attestedCredentialData
        )
        let attestationObject = AttestationObjectBuilder.buildFormatNone(authenticatorData: authenticatorData)

        let request = SavePasskeyRequest(
            credentialId: credentialId,
            rpId: input.rpId,
            rpDisplayName: input.rpDisplayName,
            userHandle: input.userHandle,
            userName: input.userName,
            userDisplayName: input.userDisplayName,
            isDiscoverable: input.isDiscoverable,
            privateKey: privateKey.rawRepresentation,  // 32-byte scalar; repo encrypts with DEK
            signCount: Self.initialSignCount,
            displayName: input.userDisplayName ?? input.userName,
            createdAt: now()
        )

        return PasskeyCreateResult(
            credentialId: credentialId,
            credentialIdBytes: credentialIdBytes,
            publicKeyCose: publicKeyCose,
            authenticatorData: authenticatorData,
            attestationObject: attestationObject,
            savePasskeyRequest: request
        )
    }

    /// 32 cryptographically random bytes for a fresh credential id (CryptoKit CSPRNG).
    public static func randomCredentialId() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
}
