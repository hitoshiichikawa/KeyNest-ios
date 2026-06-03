import Foundation

/// Plaintext representation of a single custom field associated with a credential.
/// Direct port of KeyNest's `CustomField.kt` (Issue #66).
///
/// Carries a plaintext `value` and therefore MUST NOT appear on the plain
/// `Credential` aggregate — it is reachable only via `PlaintextCredential`
/// (post-unlock) and the use-case input DTOs.
public struct CustomField: Equatable, Sendable {
    public let fieldKey: String
    public let value: String

    public init(fieldKey: String, value: String) {
        self.fieldKey = fieldKey
        self.value = value
    }
}

extension CustomField: CustomStringConvertible {
    /// Redacts both key and value — only lengths are exposed (parity with the
    /// Kotlin `toString` redaction, NFR 1.1).
    public var description: String {
        "CustomField(fieldKey=<redacted \(fieldKey.count) chars>, value=<redacted \(value.count) chars>)"
    }
}
