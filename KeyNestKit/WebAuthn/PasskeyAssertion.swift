import Foundation
import CryptoKit

/// Input for [PasskeyAssertion.sign]. Port of KeyNest Android's
/// `PasskeyAssertionInput`, with the key iOS difference: the OS provides
/// [clientDataHash] directly (we do not synthesize `clientDataJSON`), so the
/// signed message is `authenticatorData ‖ clientDataHash` verbatim
/// (design §PassKey).
public struct PasskeyAssertionInput: Sendable {
    public let rpId: String
    /// SHA-256 of the client data, supplied by the OS passkey request.
    public let clientDataHash: Data
    /// The **new** signCount from `PasskeyRepository.signWithIncrement`.
    public let signCount: Int64
    /// The plaintext P-256 private key (`rawRepresentation`) from
    /// `PasskeyRepository.loadPrivateKey`. The caller wipes it after use.
    public let privateKey: Data

    public init(rpId: String, clientDataHash: Data, signCount: Int64, privateKey: Data) {
        self.rpId = rpId
        self.clientDataHash = clientDataHash
        self.signCount = signCount
        self.privateKey = privateKey
    }
}

/// Output of [PasskeyAssertion.sign].
/// - [authenticatorData]: 37-byte `rpIdHash(32) ‖ flags(0x05) ‖ signCount(4 BE)`
///   (no attestedCredentialData, no extensions).
/// - [signature]: ASN.1 **DER**-encoded ES256 signature (WebAuthn §6.3.3; iOS
///   `ASPasskeyAssertionCredential` accepts DER).
public struct PasskeyAssertionResult: Sendable, Equatable {
    public let authenticatorData: Data
    public let signature: Data

    public init(authenticatorData: Data, signature: Data) {
        self.authenticatorData = authenticatorData
        self.signature = signature
    }
}

/// Failures raised by [PasskeyAssertion.sign].
public enum PasskeyAssertionError: Error, Equatable {
    case encoding
    case invalidPrivateKey
    case signFailed
}

/// WebAuthn authentication-ceremony signing (Req 6.3). Port of KeyNest Android's
/// `PasskeyAssertion`, reusing the byte-verified `AuthenticatorDataBuilder`.
///
/// iOS difference: the OS passes a `clientDataHash`, so the signed message is
/// `authenticatorData ‖ clientDataHash` (no `clientDataJSON` round trip). The
/// signature is computed with CryptoKit P-256 (ES256 = ECDSA/SHA-256) and
/// returned in DER form.
public enum PasskeyAssertion {
    /// UP | UV. AT/ED/BE/BS = 0. Identical to `AuthenticatorDataBuilder.flagsAssertion`.
    public static let flagsAssertion: UInt8 = 0x05

    private static let signCountMax: Int64 = 0xFFFF_FFFF

    public static func sign(_ input: PasskeyAssertionInput) throws -> PasskeyAssertionResult {
        guard input.signCount >= 0, input.signCount <= signCountMax else {
            throw PasskeyAssertionError.encoding
        }

        let rpIdHash = AuthenticatorDataBuilder.rpIdHash(input.rpId)
        let authenticatorData = AuthenticatorDataBuilder.build(
            rpIdHash: rpIdHash,
            flags: flagsAssertion,
            signCount: UInt32(input.signCount),
            attestedCredentialData: nil
        )

        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(rawRepresentation: input.privateKey)
        } catch {
            throw PasskeyAssertionError.invalidPrivateKey
        }

        do {
            // signature(for:) hashes the data with SHA-256 then signs (ES256),
            // i.e. ECDSA over SHA-256(authenticatorData ‖ clientDataHash) —
            // byte-equivalent to KeyNest's SHA256withECDSA update(authData)+update(hash).
            let signature = try privateKey.signature(for: authenticatorData + input.clientDataHash)
            return PasskeyAssertionResult(
                authenticatorData: authenticatorData,
                signature: signature.derRepresentation
            )
        } catch {
            throw PasskeyAssertionError.signFailed
        }
    }
}
