import XCTest
@testable import KeyNestKit

/// Unit tests for `GetDeviceLockStatusUseCase` (Phase 2.2 / 2.3). The real
/// `LAContext`-based `BiometricAuthenticator` needs a device; here the use case
/// is exercised through a stub `BiometricAuthenticating`.
final class GetDeviceLockStatusUseCaseTests: XCTestCase {

    func test_returnsAuthenticatorReportedStatus() {
        for status in [DeviceLockStatus.biometricAndDeviceCredential, .deviceCredentialOnly, .noLock] {
            let useCase = GetDeviceLockStatusUseCase(authenticator: StubBiometric(status: status))
            XCTAssertEqual(useCase(), status)
        }
    }
}

private struct StubBiometric: BiometricAuthenticating {
    let status: DeviceLockStatus
    func availability() -> BiometricAvailability { .ready }
    func deviceLockStatus() -> DeviceLockStatus { status }
    func authenticate(reason: String) async -> AuthResult { .succeeded }
}
