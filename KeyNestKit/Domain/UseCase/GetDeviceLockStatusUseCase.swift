import Foundation

/// Snapshots the device's biometric + lock-screen configuration for the Settings
/// screen. Port of KeyNest Android's `GetDeviceLockStatusUseCase` — the
/// `BiometricManager` probe is replaced by [BiometricAuthenticating.deviceLockStatus]
/// (LAContext-based). Synchronous and cheap.
public struct GetDeviceLockStatusUseCase {
    private let authenticator: BiometricAuthenticating

    public init(authenticator: BiometricAuthenticating) {
        self.authenticator = authenticator
    }

    public func callAsFunction() -> DeviceLockStatus {
        authenticator.deviceLockStatus()
    }
}
