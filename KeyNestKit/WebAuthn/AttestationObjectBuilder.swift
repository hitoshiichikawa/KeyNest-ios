import Foundation

/// Builds the WebAuthn attestation object using the `none` format (self
/// attestation, no certificate chain). Direct port of KeyNest's
/// `AttestationObjectBuilder.kt`.
///
/// CBOR map (3 entries, header `0xA3`, WebAuthn ordering):
///   "fmt"      = "none"
///   "attStmt"  = {}            (empty map, 0xA0)
///   "authData" = <byte string> (the full authenticator data)
public enum AttestationObjectBuilder {
    public static func buildFormatNone(authenticatorData: Data) -> Data {
        CborWriter()
            .writeMapHeader(3)
            .writeTextString("fmt").writeTextString("none")
            .writeTextString("attStmt").writeMapHeader(0)
            .writeTextString("authData").writeByteString(authenticatorData)
            .toData()
    }
}
