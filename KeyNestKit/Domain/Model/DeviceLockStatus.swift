import Foundation

/// Read-only summary of the device's lock / biometric configuration, rendered as
/// one localized string on the Settings screen. Port of KeyNest Android's
/// `DeviceLockStatus`, adapted to iOS's `LocalAuthentication` semantics.
///
/// The app intentionally offers no in-app toggle for these states — changing the
/// device lock method is delegated to iOS Settings.
///
/// Mapping from `LAContext.canEvaluatePolicy` is performed by
/// `BiometricAuthenticator.deviceLockStatus()`. Android's `UpdateRequired`
/// variant has no clean iOS equivalent (there is no "biometric security update
/// required" state exposed by `LAContext`), so it is intentionally omitted.
public enum DeviceLockStatus: Sendable, Equatable {
    /// Biometry (Face ID / Touch ID) is enrolled. On iOS this implies a device
    /// passcode is also set, so it maps to KeyNest's "biometric + device credential".
    case biometricAndDeviceCredential

    /// A device passcode is set but no biometry is enrolled / available.
    case deviceCredentialOnly

    /// No passcode and no biometry — the device has no lock screen.
    case noLock
}
