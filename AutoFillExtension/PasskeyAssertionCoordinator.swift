import AuthenticationServices
import Foundation
import KeyNestKit

/// Drives the passkey assertion (authentication) ceremony.
///
/// Flow:
/// 1. Resolve the matching `Passkey` row (by `credentialId` if
///    `allowedCredentials` constrained the lookup, otherwise a discoverable
///    pick by `rpId`).
/// 2. **RP-spoof check** (Req 6.3 parity with Android): stored `rpId` MUST
///    equal the request's `relyingPartyIdentifier`. Mismatch → generic failure
///    (no detail to the RP).
/// 3. Pre-load and decrypt the private key (`loadPrivateKey` is async; the
///    sign closure must stay synchronous so it can run on GRDB's writer).
/// 4. `signWithIncrement` opens a DB transaction, bumps `signCount`, reads
///    the new value, and hands it to the sign closure. The closure builds
///    `authenticatorData` + signs `authData ‖ clientDataHash` via
///    `PasskeyAssertion.sign`. Failures roll back so the counter never
///    advances past a bad signature (Req 6.5).
/// 5. Wipe the plaintext key buffer (`defer`) and return an
///    `ASPasskeyAssertionCredential` for the OS to deliver.
@available(iOS 17, *)
@MainActor
final class PasskeyAssertionCoordinator {
    enum Outcome {
        case success(ASPasskeyAssertionCredential)
        case notFound
        case rpMismatch
        case failed(reason: String)
    }

    private let services: ServiceLocator

    init(services: ServiceLocator) {
        self.services = services
    }

    /// Resolves the passkey to authenticate with. When `allowedCredentialIDs`
    /// is non-empty, only those credentialIds are considered (parity with
    /// WebAuthn `allowCredentials`). Otherwise the first discoverable passkey
    /// for `rpId` (most-recently-used) is used.
    func pickCandidate(
        rpId: String,
        allowedCredentialIDs: [Data]
    ) async -> Passkey? {
        do {
            if !allowedCredentialIDs.isEmpty {
                for raw in allowedCredentialIDs {
                    let id = Base64URL.encode(raw)
                    if let passkey = try await services.passkeyRepository.findByCredentialId(id) {
                        return passkey
                    }
                }
                return nil
            }
            return try await services.passkeyRepository
                .listDiscoverableByRpId(rpId)
                .first
        } catch {
            return nil
        }
    }

    func signAssertion(
        passkey: Passkey,
        request: ASPasskeyCredentialRequest
    ) async -> Outcome {
        let requestedRp = (request.credentialIdentity as? ASPasskeyCredentialIdentity)?
            .relyingPartyIdentifier
        guard let requestedRp, requestedRp == passkey.rpId else {
            return .rpMismatch
        }

        let credentialId = passkey.credentialId
        let clientDataHash = request.clientDataHash

        let keyData: Data?
        do {
            keyData = try await services.passkeyRepository.loadPrivateKey(credentialId: credentialId)
        } catch {
            return .failed(reason: String(describing: type(of: error)))
        }
        guard var keyBuffer = keyData else {
            return .notFound
        }
        defer { keyBuffer.resetBytes(in: 0..<keyBuffer.count) }

        // Capture the buffer as a `let` snapshot so the @Sendable closure
        // can use it without holding a mutable binding.
        let keySnapshot = keyBuffer
        let rpIdSnapshot = passkey.rpId
        let clientDataHashSnapshot = clientDataHash
        do {
            let signed: PasskeyAssertionResult = try await services.passkeyRepository.signWithIncrement(
                credentialId: credentialId
            ) { newCount in
                let input = PasskeyAssertionInput(
                    rpId: rpIdSnapshot,
                    clientDataHash: clientDataHashSnapshot,
                    signCount: newCount,
                    privateKey: keySnapshot
                )
                return try PasskeyAssertion.sign(input)
            }
            let credentialIDBytes = Base64URL.decode(passkey.credentialId) ?? Data()
            let response = ASPasskeyAssertionCredential(
                userHandle: passkey.userHandle,
                relyingParty: passkey.rpId,
                signature: signed.signature,
                clientDataHash: clientDataHash,
                authenticatorData: signed.authenticatorData,
                credentialID: credentialIDBytes
            )
            return .success(response)
        } catch RepositoryError.notFound {
            return .notFound
        } catch {
            return .failed(reason: String(describing: type(of: error)))
        }
    }
}
