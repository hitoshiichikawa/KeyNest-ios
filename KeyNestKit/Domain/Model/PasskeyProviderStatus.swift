import Foundation

/// Three-valued state of KeyNest's registration as a system passkey provider.
/// Port of KeyNest Android's `PasskeyProviderStatus`, adapted to iOS:
///
/// - [enabled]: iOS 17+ and KeyNest is enabled as an AutoFill credential
///   provider that advertises passkeys.
/// - [disabled]: iOS 17+ but KeyNest is not currently enabled (or a status probe
///   failed — fail-safe default).
/// - [unsupported]: running below iOS 17 (the passkey-provider OS floor). The
///   app's deployment target is iOS 17, so this is a neutral edge state.
///
/// UI-agnostic: string selection and OS probing live in the Settings layer.
public enum PasskeyProviderStatus: Sendable, Equatable {
    case enabled
    case disabled
    case unsupported
}
