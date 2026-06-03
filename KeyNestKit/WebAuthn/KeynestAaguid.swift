import Foundation

/// The 16-byte AAGUID identifying KeyNest (iOS) as the authenticator in attested
/// credential data. Structure ported from KeyNest Android's `KeynestAaguid.kt`,
/// but the iOS build mints its **own** AAGUID (decision: new AAGUID, not reused).
///
/// UUID: `aae6363e-fdb4-4c71-aef4-43c79e5d59a3` (big-endian 16 bytes).
/// This must stay fixed forever — it identifies the KeyNest iOS authenticator
/// model.
public enum KeynestAaguid {
    private static let value = Data([
        0xAA, 0xE6, 0x36, 0x3E,
        0xFD, 0xB4, 0x4C, 0x71,
        0xAE, 0xF4, 0x43, 0xC7,
        0x9E, 0x5D, 0x59, 0xA3,
    ])

    /// Returns a defensive copy of the 16-byte AAGUID.
    public static func bytes() -> Data { value }
}
