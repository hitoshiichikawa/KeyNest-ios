import Foundation

/// Base64url (RFC 4648 §5) without padding — the encoding WebAuthn uses for
/// credential ids and other binary fields. Parity with the Android registration
/// ceremony's `Base64.URL_SAFE | NO_PADDING | NO_WRAP`.
public enum Base64URL {
    /// Encodes [data] as base64url with no `=` padding.
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes a base64url string (with or without padding), or nil if invalid.
    public static func decode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder != 0 {
            s += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: s)
    }
}
