import Foundation
import LocalAuthentication

/// Result of a biometric / device-owner authentication attempt. Port of KeyNest
/// Android's `AuthResult`; callers branch deterministically without catching
/// exceptions.
public enum AuthResult: Sendable, Equatable {
    /// Biometric or passcode auth succeeded — the caller may proceed to decrypt.
    case succeeded
    /// The user dismissed the prompt (cancel / system cancel / app cancel).
    case cancelled
    /// Auth failed unrecoverably (e.g. lockout). `message` is the LA framework
    /// string (never user secrets).
    case failed(code: Int, message: String)
    /// The device cannot authenticate (no passcode / biometry).
    case unavailable(BiometricAvailability)
}

/// Whether device-owner authentication is currently possible.
public enum BiometricAvailability: Sendable, Equatable {
    /// Ready to prompt (biometry and/or passcode usable).
    case ready
    /// No biometry enrolled and/or no passcode set.
    case notEnrolled
    /// No supported authentication hardware / otherwise unavailable.
    case notAvailable
}

/// Abstraction over device-owner authentication so use cases and view models can
/// be unit-tested with a fake. Implemented by [BiometricAuthenticator].
public protocol BiometricAuthenticating {
    /// Whether a prompt can currently succeed.
    func availability() -> BiometricAvailability
    /// The device's lock configuration, for the Settings screen.
    func deviceLockStatus() -> DeviceLockStatus
    /// Presents the system prompt and resolves to an [AuthResult].
    func authenticate(reason: String) async -> AuthResult
}

/// `LocalAuthentication` wrapper around device-owner authentication
/// (`LAPolicy.deviceOwnerAuthentication` = biometrics with passcode fallback).
/// iOS equivalent of KeyNest Android's `BiometricAuthenticator`
/// (`BIOMETRIC_STRONG | DEVICE_CREDENTIAL`).
///
/// A fresh `LAContext` is created per operation (a context caches its evaluation
/// after first use, so reusing one across prompts would suppress re-auth).
///
/// > Verify on a device: `LAContext` evaluation requires real hardware /
/// > simulator biometrics enrollment. Unit tests exercise consumers through the
/// > [BiometricAuthenticating] protocol with a fake.
public final class BiometricAuthenticator: BiometricAuthenticating {
    private let contextProvider: () -> LAContext

    public init(contextProvider: @escaping () -> LAContext = { LAContext() }) {
        self.contextProvider = contextProvider
    }

    public func availability() -> BiometricAvailability {
        let context = contextProvider()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .ready
        }
        return Self.mapAvailability(error)
    }

    public func deviceLockStatus() -> DeviceLockStatus {
        let context = contextProvider()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // Biometry enrolled ⇒ a passcode is also set on iOS.
            return .biometricAndDeviceCredential
        }
        var passcodeError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &passcodeError) {
            return .deviceCredentialOnly
        }
        return .noLock
    }

    public func authenticate(reason: String) async -> AuthResult {
        let context = contextProvider()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            return .unavailable(Self.mapAvailability(availabilityError))
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .succeeded : .failed(code: -1, message: "evaluation returned false")
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel:
                return .cancelled
            default:
                return .failed(code: laError.code.rawValue, message: laError.localizedDescription)
            }
        } catch {
            // Non-LAError: surface the type name only (never the message — NFR 1.1).
            return .failed(code: -1, message: String(describing: type(of: error)))
        }
    }

    private static func mapAvailability(_ error: NSError?) -> BiometricAvailability {
        guard let laError = error as? LAError else { return .notAvailable }
        switch laError.code {
        case .biometryNotEnrolled, .passcodeNotSet:
            return .notEnrolled
        default:
            return .notAvailable
        }
    }
}
