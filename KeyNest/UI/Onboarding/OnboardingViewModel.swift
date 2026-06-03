import Foundation
import Observation
import AuthenticationServices
import KeyNestKit

/// Backs the first-run onboarding screen. iOS port of Android
/// `AutofillEnableActivity`.
///
/// Behaviour parity:
/// - Re-samples `ASCredentialIdentityStore.state()` whenever the app
///   foregrounds (Android `onResume` equivalent). The user typically
///   leaves to Settings.app and returns, so the "already enabled" state
///   must surface immediately on return.
/// - PassKey provider status is derived from OS version + AutoFill state
///   (parity with `SettingsViewModel.derivePasskeyStatus`).
@MainActor
@Observable
final class OnboardingViewModel {
    var autofillEnabled: Bool = false
    var passkeyStatus: PasskeyProviderStatus = .unsupported

    @ObservationIgnored private let identityStore: ASCredentialIdentityStore

    init(identityStore: ASCredentialIdentityStore = .shared) {
        self.identityStore = identityStore
    }

    func refresh() async {
        let state = await identityStore.state()
        autofillEnabled = state.isEnabled
        if #available(iOS 17, *) {
            passkeyStatus = state.isEnabled ? .enabled : .disabled
        } else {
            passkeyStatus = .unsupported
        }
    }
}
