import Foundation

/// One item in the "what should we insert?" picker that iOS 18+ shows
/// after the user picks `KeyNest → ...` from the keyboard insertion menu.
///
/// Each entry carries the user-visible label and the raw value to paste.
/// The value is **short-lived** — the picker hands it to
/// `completeRequest(withTextToInsert:)` immediately after the user taps,
/// matching the `PlaintextCredential` lifecycle (the caller closes the
/// plaintext right after building the option list).
public struct InsertableTextField: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case username
        case password
        case customField(key: String)
    }
    public let id: String
    public let displayName: String
    public let value: String
    public let kind: Kind

    public init(id: String, displayName: String, value: String, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.value = value
        self.kind = kind
    }

    /// True when the value should never be cached / logged. Drives the
    /// `.privacySensitive()` annotation in the SwiftUI picker.
    public var isSensitive: Bool {
        switch kind {
        case .password, .customField: return true
        case .username:               return false
        }
    }
}

/// Builds the "insertable fields" list from a freshly-unlocked
/// `PlaintextCredential`.
///
/// Order:
/// 1. `username` (omitted if blank — nothing useful to paste)
/// 2. `password` (omitted if blank)
/// 3. Each custom field whose `value` is non-empty, in stored order.
///
/// The username is treated as **non-sensitive** for clipboard policy
/// purposes, password / custom field values as **sensitive**. The picker
/// view should hide the value behind a "tap to insert" affordance for
/// sensitive entries and show it inline for non-sensitive ones.
public enum TextToInsertOptions {
    public static func options(from plaintext: PlaintextCredential) -> [InsertableTextField] {
        var out: [InsertableTextField] = []

        let user = plaintext.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty {
            out.append(InsertableTextField(
                id: "username",
                displayName: "Username",
                value: user,
                kind: .username
            ))
        }

        let password = String(decoding: plaintext.password, as: UTF8.self)
        if !password.isEmpty {
            out.append(InsertableTextField(
                id: "password",
                displayName: "Password",
                value: password,
                kind: .password
            ))
        }

        for field in plaintext.customFields where !field.value.isEmpty {
            let key = field.fieldKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = key.isEmpty ? "Custom" : key
            out.append(InsertableTextField(
                id: "custom:\(field.fieldKey)",
                displayName: label,
                value: field.value,
                kind: .customField(key: field.fieldKey)
            ))
        }

        return out
    }
}
