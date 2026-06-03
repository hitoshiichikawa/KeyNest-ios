import AuthenticationServices
import Foundation
import KeyNestKit

/// Drives the passkey-registration ceremony inside the AutoFill extension.
///
/// Lives outside the view controller so the view layer only has to focus on
/// rendering the confirm sheet + biometric prompt orchestration. iOS 17+ only.
@available(iOS 17, *)
@MainActor
final class PasskeyRegistrationCoordinator {
    enum Outcome {
        case success(ASPasskeyRegistrationCredential)
        case cancelled
        case failed(reason: String)
    }

    private let services: ServiceLocator

    init(services: ServiceLocator) {
        self.services = services
    }

    /// Builds and persists the passkey. The caller has already shown a confirm
    /// UI and obtained user assent + biometric success.
    ///
    /// Steps:
    /// 1. Build COSE / attestation bytes with `PasskeyCreator`.
    /// 2. Persist the encrypted private key via `PasskeyRepository.save`.
    ///    `Req 6.6` overwrite-on-duplicate (`rpId`+`userHandle`) is handled
    ///    inside the repository.
    /// 3. Wipe the plaintext key buffer (NFR 1.1).
    /// 4. Return an `ASPasskeyRegistrationCredential` for the OS to ship to
    ///    the requesting RP. The `clientDataHash` is provided by iOS — we do
    ///    NOT compose `clientDataJSON` ourselves (design §PassKey).
    func register(request: ASPasskeyCredentialRequest) async -> Outcome {
        let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity
        guard let identity else {
            return .failed(reason: "Unexpected credentialIdentity shape")
        }

        let input = PasskeyCreateInput(
            rpId: identity.relyingPartyIdentifier,
            rpDisplayName: nil,
            userHandle: identity.userHandle,
            userName: identity.userName,
            userDisplayName: identity.userName,
            isDiscoverable: true
        )

        let result: PasskeyCreateResult
        do {
            result = try services.passkeyCreator.create(input)
        } catch {
            return .failed(reason: String(describing: type(of: error)))
        }

        var saveRequest = result.savePasskeyRequest
        do {
            try await services.passkeyRepository.save(saveRequest)
        } catch {
            // Wipe the plaintext key even on failure (NFR 1.1).
            saveRequest.privateKey.resetBytes(in: 0..<saveRequest.privateKey.count)
            return .failed(reason: String(describing: type(of: error)))
        }
        saveRequest.privateKey.resetBytes(in: 0..<saveRequest.privateKey.count)

        let credential = ASPasskeyRegistrationCredential(
            relyingParty: identity.relyingPartyIdentifier,
            clientDataHash: request.clientDataHash,
            credentialID: result.credentialIdBytes,
            attestationObject: result.attestationObject
        )
        return .success(credential)
    }
}
