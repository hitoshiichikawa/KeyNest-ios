import Foundation
import CryptoKit

/// Builds WebAuthn authenticator data. Direct port of KeyNest's
/// `AuthenticatorDataBuilder.kt`. Byte layout (WebAuthn §6.1):
///
///   rpIdHash (32) ‖ flags (1) ‖ signCount (4, big-endian) ‖ [attestedCredentialData] ‖ [extensions]
///
/// Flags used by KeyNest:
///   - registration : 0x45 = UP | UV | AT
///   - assertion    : 0x05 = UP | UV
public enum AuthenticatorDataBuilder {
    public static let flagsRegistration: UInt8 = 0x45
    public static let flagsAssertion: UInt8 = 0x05

    /// SHA-256 of the RP ID (UTF-8). 32 bytes.
    public static func rpIdHash(_ rpId: String) -> Data {
        Data(SHA256.hash(data: Data(rpId.utf8)))
    }

    /// Assembles authenticator data. `rpIdHash` must be 32 bytes; `signCount`
    /// must fit an unsigned 32-bit integer.
    public static func build(
        rpIdHash: Data,
        flags: UInt8,
        signCount: UInt32,
        attestedCredentialData: Data? = nil,
        extensions: Data? = nil
    ) -> Data {
        precondition(rpIdHash.count == 32, "rpIdHash must be 32 bytes")
        var out = Data()
        out.append(rpIdHash)
        out.append(flags)
        var be = signCount.bigEndian
        withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
        if let attestedCredentialData { out.append(attestedCredentialData) }
        if let extensions { out.append(extensions) }
        return out
    }

    /// Builds attested credential data (registration only):
    ///   AAGUID (16) ‖ credIdLen (2, big-endian) ‖ credentialId ‖ publicKeyCose
    public static func attestedCredentialData(
        aaguid: Data,
        credentialId: Data,
        publicKeyCose: Data
    ) -> Data {
        precondition(aaguid.count == 16, "AAGUID must be 16 bytes")
        precondition(credentialId.count <= 0xFFFF, "credentialId too long")
        var out = Data()
        out.append(aaguid)
        var len = UInt16(credentialId.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(credentialId)
        out.append(publicKeyCose)
        return out
    }
}
