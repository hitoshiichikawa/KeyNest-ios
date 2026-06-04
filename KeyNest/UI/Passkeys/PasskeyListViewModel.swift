import Foundation
import KeyNestKit

/// Observes stored passkeys for the main-app vault screen. Mirrors the
/// `CredentialListViewModel` shape so the list view can stay simple.
@MainActor
@Observable
final class PasskeyListViewModel {
    private(set) var passkeys: [Passkey] = []
    private(set) var error: String?

    private let services: ServiceLocator

    init(services: ServiceLocator) {
        self.services = services
    }

    func observe() async {
        do {
            for try await snapshot in services.listPasskeys() {
                passkeys = snapshot
            }
        } catch {
            self.error = String(describing: type(of: error))
        }
    }

    func delete(_ passkey: Passkey) async {
        do {
            try await services.passkeyRepository.delete(credentialId: passkey.credentialId)
        } catch {
            self.error = String(describing: type(of: error))
        }
    }
}
