import Foundation

/// Encodes an ES256 (P-256) public key as a COSE_Key CBOR map (RFC 8152 §13.1).
/// Direct port of KeyNest's `CoseKeyEncoder.kt` — the map ordering and the
/// fixed-length 32-byte coordinates must match byte-for-byte.
///
/// Resulting map (5 entries, COSE ordering, header `0xA5`):
///   1  (kty) = 2  (EC2)
///   3  (alg) = -7 (ES256)
///  -1  (crv) = 1  (P-256)
///  -2  (x)   = 32-byte big-endian X coordinate
///  -3  (y)   = 32-byte big-endian Y coordinate
public enum CoseKeyEncoder {
    public enum CoseError: Error { case invalidCoordinateLength }

    /// - Parameters:
    ///   - x: 32-byte big-endian X coordinate (left-padded with zeros if needed).
    ///   - y: 32-byte big-endian Y coordinate.
    public static func encodeEs256(x: Data, y: Data) throws -> Data {
        let xb = try fixedLength(x, 32)
        let yb = try fixedLength(y, 32)
        return CborWriter()
            .writeMapHeader(5)
            .writeUnsignedInt(1).writeUnsignedInt(2)      // kty = EC2
            .writeUnsignedInt(3).writeNegativeInt(-7)     // alg = ES256
            .writeNegativeInt(-1).writeUnsignedInt(1)     // crv = P-256
            .writeNegativeInt(-2).writeByteString(xb)     // x
            .writeNegativeInt(-3).writeByteString(yb)     // y
            .toData()
    }

    /// Convenience: split a 64-byte uncompressed coordinate pair (x‖y) — e.g.
    /// `P256.Signing.PublicKey.rawRepresentation` — into the COSE map.
    public static func encodeEs256(rawXY: Data) throws -> Data {
        guard rawXY.count == 64 else { throw CoseError.invalidCoordinateLength }
        let x = rawXY.prefix(32)
        let y = rawXY.suffix(32)
        return try encodeEs256(x: Data(x), y: Data(y))
    }

    /// Left-pads (or validates) `data` to exactly `length` bytes. Rejects
    /// anything longer — mirrors `toUnsignedFixedLength` in the Kotlin source.
    private static func fixedLength(_ data: Data, _ length: Int) throws -> Data {
        if data.count == length { return data }
        if data.count < length {
            return Data(repeating: 0, count: length - data.count) + data
        }
        // Allow a single leading 0x00 sign byte to be stripped (BigInteger parity).
        if data.count == length + 1, data.first == 0x00 {
            return data.dropFirst()
        }
        throw CoseError.invalidCoordinateLength
    }
}
