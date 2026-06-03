import Foundation
import os

/// Logging wrapper that mechanically prevents sensitive data from leaking to the
/// unified log / crash reports. Swift counterpart of KeyNest Android's
/// `SafeLogger.kt`.
///
/// Contract (parity with KeyNest NFR 1.1 / the Android `SafeLogger`):
/// - Callers pass only **static, non-sensitive** message strings. Plaintext
///   passwords, decrypted bytes, custom-field values, private-key material and
///   full signature hex MUST NOT be interpolated into the message.
/// - When an `Error` is attached, only its **type name** is forwarded — never
///   `localizedDescription`, which can echo offending input.
///
/// All interpolations are marked `privacy: .public` deliberately: the values we
/// forward (a constant message + an error type name) are safe by construction,
/// so we opt out of the redaction placeholder the unified log would otherwise
/// apply to dynamic strings.
public enum SafeLog {
    private static let logger = Logger(
        subsystem: "io.github.hitoshiichikawa.ios.keynest",
        category: "KeyNest"
    )

    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public static func warn(_ message: String, error: Error? = nil) {
        if let error {
            logger.warning("\(message, privacy: .public) (cause=\(typeName(of: error), privacy: .public))")
        } else {
            logger.warning("\(message, privacy: .public)")
        }
    }

    public static func error(_ message: String, error: Error? = nil) {
        if let error {
            logger.error("\(message, privacy: .public) (cause=\(typeName(of: error), privacy: .public))")
        } else {
            logger.error("\(message, privacy: .public)")
        }
    }

    /// The concrete type name of an error, e.g. `DecodingError`. Never the
    /// error's message — that can echo sensitive input (parity with the Android
    /// `SafeLogger` which forwards `throwable.javaClass.simpleName` only).
    private static func typeName(of error: Error) -> String {
        String(describing: type(of: error))
    }
}
