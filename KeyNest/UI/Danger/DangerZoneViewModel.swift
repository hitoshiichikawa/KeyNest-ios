import Foundation
import Observation
import KeyNestKit

/// Backs the Danger Zone screen. iOS port of Android `DangerZoneViewModel`,
/// preserving its strict state machine:
///
///   idle ──tap──▶ authenticating ──success──▶ confirming ──confirm──▶ clearing ──ok──▶ cleared
///                       │                          │                       │
///                  cancel/fail                  cancel                  failure
///                       ▼                          ▼                       ▼
///                  idle / failed             idle                       failed
///
/// `clearing` is only reachable from `confirming`, which is only reachable
/// from a successful biometric prompt. The vault is never wiped without
/// both gates (Req 7.4: device-owner auth + explicit confirmation).
@MainActor
@Observable
final class DangerZoneViewModel {
    enum Phase: Equatable {
        case idle
        case authenticating
        case confirming
        case clearing
        case cleared
        case failed(reason: String)
    }

    var phase: Phase = .idle

    @ObservationIgnored private let services: ServiceLocator

    init(services: ServiceLocator) {
        self.services = services
    }

    func startClearFlow() async {
        switch phase {
        case .idle, .failed, .cleared:
            break
        default:
            return
        }
        phase = .authenticating

        let auth = await services.biometricAuthenticator
            .authenticate(reason: "Authenticate to clear the vault")
        switch auth {
        case .succeeded:
            phase = .confirming
        case .cancelled:
            phase = .idle
        case .failed(_, let message):
            phase = .failed(reason: message)
        case .unavailable:
            phase = .failed(reason: "Device authentication is not available.")
        }
    }

    func cancelConfirmation() {
        if phase == .confirming { phase = .idle }
    }

    /// Confirmed → run the use case. Must be called only from the
    /// `.confirming` state (the View guards this through `confirmationDialog`).
    func confirmAndClear() async {
        guard phase == .confirming else { return }
        phase = .clearing
        do {
            try await services.clearVault()
            await services.identityStoreSync.removeAll()
            phase = .cleared
        } catch {
            phase = .failed(reason: String(describing: type(of: error)))
        }
    }
}
