import Foundation

/// Minimal CBOR (RFC 8949) writer — a direct port of KeyNest's `CborWriter.kt`.
///
/// Only the major types the WebAuthn ceremonies need are implemented:
/// unsigned int (0), negative int (1), byte string (2), text string (3),
/// array (4) and map (5). No external CBOR dependency, byte-for-byte parity
/// with the Android implementation so attestation / assertion blobs are
/// identical across platforms.
public final class CborWriter {
    private var buffer = Data()

    public init() {}

    @discardableResult
    public func writeUnsignedInt(_ value: Int) -> CborWriter {
        precondition(value >= 0, "writeUnsignedInt requires a non-negative value")
        writeTypeAndLength(majorType: 0, length: UInt64(value))
        return self
    }

    /// Encodes a CBOR negative integer. `value` is the actual negative number
    /// (e.g. -7 for ES256); CBOR stores `-1 - value` under major type 1.
    @discardableResult
    public func writeNegativeInt(_ value: Int) -> CborWriter {
        precondition(value < 0, "writeNegativeInt requires a negative value")
        writeTypeAndLength(majorType: 1, length: UInt64(-1 - value))
        return self
    }

    @discardableResult
    public func writeByteString(_ bytes: Data) -> CborWriter {
        writeTypeAndLength(majorType: 2, length: UInt64(bytes.count))
        buffer.append(bytes)
        return self
    }

    @discardableResult
    public func writeTextString(_ text: String) -> CborWriter {
        let utf8 = Data(text.utf8)
        writeTypeAndLength(majorType: 3, length: UInt64(utf8.count))
        buffer.append(utf8)
        return self
    }

    @discardableResult
    public func writeArrayHeader(_ count: Int) -> CborWriter {
        precondition(count >= 0)
        writeTypeAndLength(majorType: 4, length: UInt64(count))
        return self
    }

    @discardableResult
    public func writeMapHeader(_ count: Int) -> CborWriter {
        precondition(count >= 0)
        writeTypeAndLength(majorType: 5, length: UInt64(count))
        return self
    }

    public func toData() -> Data { buffer }

    // MARK: - Length / header encoding (RFC 8949 §3)

    private func writeTypeAndLength(majorType: UInt8, length: UInt64) {
        let mt = majorType << 5
        switch length {
        case 0...23:
            buffer.append(mt | UInt8(length))
        case 24...0xFF:
            buffer.append(mt | 24)
            buffer.append(UInt8(length))
        case 0x100...0xFFFF:
            buffer.append(mt | 25)
            appendBigEndian(UInt16(length))
        case 0x1_0000...0xFFFF_FFFF:
            buffer.append(mt | 26)
            appendBigEndian(UInt32(length))
        default:
            buffer.append(mt | 27)
            appendBigEndian(length)
        }
    }

    private func appendBigEndian(_ value: UInt16) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { buffer.append(contentsOf: $0) }
    }

    private func appendBigEndian(_ value: UInt32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { buffer.append(contentsOf: $0) }
    }

    private func appendBigEndian(_ value: UInt64) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { buffer.append(contentsOf: $0) }
    }
}
