import AuthenticationServices
import SwiftUI
import KeyNestKit

/// AutoFill Credential Provider extension entry point.
///
/// Phase 4.3 wires the **password** path; passkey registration / assertion
/// (Phase 5) will hook into the iOS 17+ unified `ASCredentialRequest` callbacks.
///
/// Flow contract (design §AutoFill):
/// 1. `prepareCredentialList(for:)` → narrow the vault to entries that match
///    the requested service identifier(s), render a SwiftUI picker.
/// 2. User picks a row → `LAContext` device-owner auth → `UnlockVaultUseCase`
///    decrypts → `completeRequest(withSelectedCredential: ASPasswordCredential)`.
/// 3. `provideCredentialWithoutUserInteraction(for:)` always rejects with
///    `.userInteractionRequired` because we gate every reveal behind a fresh
///    biometric prompt (Req 4.1).
/// 4. `prepareInterfaceToProvideCredential(for:)` is the silent-path's fallback —
///    same authenticate + unlock + return path.
///
/// NFR 3.1: any failure / cancellation closes via `cancelRequest(withError:)`
/// — the OS surfaces "no entry" instead of an error dialog.
final class CredentialProviderViewController: ASCredentialProviderViewController {

    private var services: ServiceLocator?

    private func locator() -> ServiceLocator? {
        if let services { return services }
        do {
            let s = try ServiceLocator.makeShared()
            services = s
            return s
        } catch {
            return nil
        }
    }

    // MARK: - UI path (user is picking a credential)

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        guard let services = locator() else {
            failSafely()
            return
        }
        Task {
            do {
                let snapshot = try await services.credentialRepository.listAll(sort: .updatedDesc)
                let matches = filterMatches(snapshot, requested: serviceIdentifiers)
                await MainActor.run {
                    renderList(matches: matches, all: snapshot)
                }
            } catch {
                failSafely()
            }
        }
    }

    @MainActor
    private func renderList(matches: [Credential], all: [Credential]) {
        let view = AutoFillPickerView(
            matches: matches,
            all: all,
            onSelect: { [weak self] credential in
                Task { await self?.authenticateAndFill(credential: credential) }
            },
            onCancel: { [weak self] in
                self?.cancelByUser()
            }
        )
        let host = UIHostingController(rootView: view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.assignBackground(view: self.view)
        self.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func filterMatches(
        _ all: [Credential],
        requested: [ASCredentialServiceIdentifier]
    ) -> [Credential] {
        guard !requested.isEmpty else { return all }
        let needles = requested.map { ServiceIdentifierMatcher.normalize($0.identifier) }
        return all.filter { credential in
            let stored = ServiceIdentifierMatcher.normalize(credential.serviceIdentifier)
            return !stored.isEmpty && needles.contains(stored)
        }
    }

    // MARK: - Silent path (no UI)

    /// We always require a biometric prompt before exposing plaintext
    /// (Req 4.1). Therefore the silent path simply hands control back to the
    /// OS with `.userInteractionRequired` so iOS surfaces the UI flow.
    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            )
        )
    }

    /// Silent-path UI fallback: iOS already pre-selected one credential, we
    /// authenticate, decrypt and return it (or fail safely).
    override func prepareInterfaceToProvideCredential(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        guard let services = locator(),
              let raw = credentialIdentity.recordIdentifier,
              let recordId = Int64(raw) else {
            failSafely()
            return
        }
        let id = CredentialId(recordId)
        Task {
            do {
                let credentials = try await services.credentialRepository.listAll(sort: .updatedDesc)
                if let credential = credentials.first(where: { $0.id == id }) {
                    await authenticateAndFill(credential: credential)
                } else {
                    failSafely()
                }
            } catch {
                failSafely()
            }
        }
    }

    // MARK: - Authenticate + fill

    private func authenticateAndFill(credential: Credential) async {
        guard let services else {
            failSafely()
            return
        }
        let auth = await services.biometricAuthenticator
            .authenticate(reason: "Sign in to \(credential.serviceIdentifier)")
        guard case .succeeded = auth else {
            cancelByUser()
            return
        }
        do {
            let plaintext = try await services.unlockVault(credential.id)
            let password = String(decoding: plaintext.password, as: UTF8.self)
            let user = plaintext.username
            plaintext.close()
            // Stamp lastUsedAt opportunistically; failures must not block fill.
            try? await services.markCredentialUsed(credential.id)
            await MainActor.run {
                extensionContext.completeRequest(
                    withSelectedCredential: ASPasswordCredential(user: user, password: password),
                    completionHandler: nil
                )
            }
        } catch {
            failSafely()
        }
    }

    // MARK: - Safe failure / cancel (NFR 3.1)

    private func failSafely() {
        Task { @MainActor in
            extensionContext.cancelRequest(
                withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue
                )
            )
        }
    }

    private func cancelByUser() {
        Task { @MainActor in
            extensionContext.cancelRequest(
                withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.userCanceled.rawValue
                )
            )
        }
    }
}
