import Foundation

extension Cipher {
    /// Encrypts plaintext password bytes and zero-fills the intermediate `Data`
    /// **immediately** (before the ciphertext is persisted), parity with
    /// KeyNest Android's wipe-before-save (`Arrays.fill` in a `finally`).
    ///
    /// Best-effort: Swift value semantics + `String` immutability mean the
    /// caller's own `[UInt8]` cannot be reached and wiped from here (same
    /// accepted limitation as `PlaintextCredential`). This keeps the cipher's
    /// own working copy of the plaintext as short-lived as possible.
    func encryptWipingPassword(_ password: [UInt8]) throws -> EncryptedBlob {
        var data = Data(password)
        defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
        return try encrypt(data)
    }
}
