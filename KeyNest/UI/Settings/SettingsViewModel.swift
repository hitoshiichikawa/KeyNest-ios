import Foundation
import Observation
import AuthenticationServices
import KeyNestKit

/// Backs the Settings screen. iOS port of Android `SettingsViewModel`.
///
/// Sources of truth:
/// - **Vault metadata** (`count`, `latestUpdatedAt`) → `ObserveVaultMetadataUseCase`
///   (`AsyncThrowingStream`, re-emits on every CRUD).
/// - **Vault storage usage** (bytes) → `GetVaultStorageUsageUseCase` (one-shot;
///   re-run when metadata refreshes since rows change the WAL footprint).
/// - **Device lock status** → `GetDeviceLockStatusUseCase` (LAContext snapshot;
///   sampled on `.task` and on `scenePhase == .active`).
/// - **AutoFill enabled state** → `ASCredentialIdentityStore.state()`. Re-sampled
///   when the app re-enters foreground (the user typically toggles this in
///   Settings.app and returns).
/// - **PassKey provider status** → derived from the OS version + the AutoFill
///   state (iOS < 17 = `.unsupported`; iOS 17+ = mirror AutoFill).
@MainActor
@Observable
final class SettingsViewModel {
    var vault: VaultMetadata = VaultMetadata(count: 0, latestUpdatedAt: nil)
    var storageBytes: Int64 = 0
    var lockStatus: DeviceLockStatus = .noLock
    var autofillEnabled: Bool = false
    var passkeyStatus: PasskeyProviderStatus = .unsupported

    @ObservationIgnored private let services: ServiceLocator
    @ObservationIgnored private let identityStore: ASCredentialIdentityStore

    init(
        services: ServiceLocator,
        identityStore: ASCredentialIdentityStore = .shared
    ) {
        self.services = services
        self.identityStore = identityStore
    }

    // MARK: - Observation

    /// Drives the metadata stream. View invokes from `.task`. Storage usage is
    /// re-measured each time metadata changes (an insert/delete changes the
    /// SQLite + WAL footprint).
    func observeVault() async {
        do {
            for try await metadata in services.observeVaultMetadata() {
                vault = metadata
                storageBytes = await services.getVaultStorageUsage()
            }
        } catch is CancellationError {
            return
        } catch {
            // Settings is a read-only surface; swallow and keep the last
            // good values rather than surfacing a dead-end error UI.
        }
    }

    /// Snapshot pull for the values that don't observe natively. Called from
    /// `.task` once and on every foreground re-entry.
    func refreshSnapshots() async {
        lockStatus = services.getDeviceLockStatus()
        let state = await identityStore.state()
        autofillEnabled = state.isEnabled
        passkeyStatus = derivePasskeyStatus(autofillEnabled: state.isEnabled)
    }

    private func derivePasskeyStatus(autofillEnabled: Bool) -> PasskeyProviderStatus {
        if #available(iOS 17, *) {
            return autofillEnabled ? .enabled : .disabled
        } else {
            return .unsupported
        }
    }
}
