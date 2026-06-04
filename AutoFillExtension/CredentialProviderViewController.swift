import AuthenticationServices
import SwiftUI
import KeyNestKit
import os

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

    override func viewDidLoad() {
        super.viewDidLoad()
        // Pin a placeholder before any prepareXxx callback fires so the user
        // never sees a blank canvas during the SQLite + Secure Enclave
        // warm-up that ServiceLocator.makeShared performs.
        hostConfirmView(LoadingPlaceholderView())
    }

    private var services: ServiceLocator?

    /// Async locator: ServiceLocator init opens the SQLite vault and unwraps
    /// the Secure-Enclave KEK. Each of those takes hundreds of ms on cold
    /// start, so we run them on a detached priority task and return on
    /// MainActor only after they're done — the placeholder stays visible
    /// throughout.
    private func locatorAsync() async -> ServiceLocator? {
        if let services { return services }
        let built: ServiceLocator? = await Task.detached(priority: .userInitiated) {
            try? ServiceLocator.makeShared()
        }.value
        if let built { services = built }
        return built
    }

    // MARK: - UI path (user is picking a credential)

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let rawIdentifiers = serviceIdentifiers.map(\.identifier)
        Task {
            guard let services = await locatorAsync() else {
                failSafely(reason: "ServiceLocator init failed")
                return
            }
            do {
                let snapshot = try await services.credentialRepository.listAll(sort: .updatedDesc)
                let matches = AutoFillCandidateSelection.filter(
                    all: snapshot,
                    requestedRawServiceIdentifiers: rawIdentifiers
                )
                let suggested = AutoFillCandidateSelection.suggestedServiceIdentifier(
                    from: rawIdentifiers
                )
                await MainActor.run {
                    renderList(
                        matches: matches,
                        all: snapshot,
                        suggestedServiceIdentifier: suggested,
                        services: services
                    )
                }
            } catch {
                failSafely()
            }
        }
    }

    @MainActor
    private func renderList(
        matches: [Credential],
        all: [Credential],
        suggestedServiceIdentifier: String,
        services: ServiceLocator
    ) {
        let view = AutoFillPickerView(
            matches: matches,
            all: all,
            suggestedServiceIdentifier: suggestedServiceIdentifier,
            onSelect: { [weak self] credential in
                Task { await self?.authenticateAndFill(credential: credential) }
            },
            onSaveNew: { [weak self] in
                self?.showSaveNewForm(
                    prefilledServiceIdentifier: suggestedServiceIdentifier,
                    services: services
                )
            },
            onCancel: { [weak self] in
                self?.cancelByUser()
            }
        )
        hostConfirmView(view)
    }

    @MainActor
    private func showSaveNewForm(prefilledServiceIdentifier: String, services: ServiceLocator) {
        let view = AutoFillSaveNewView(
            prefilledServiceIdentifier: prefilledServiceIdentifier,
            services: services,
            onSave: { [weak self] user, password in
                self?.completeWithSavedCredential(user: user, password: password)
            },
            onCancel: { [weak self] in self?.cancelByUser() }
        )
        hostConfirmView(view)
    }

    @MainActor
    private func completeWithSavedCredential(user: String, password: String) {
        extensionContext.completeRequest(
            withSelectedCredential: ASPasswordCredential(user: user, password: password),
            completionHandler: nil
        )
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
        guard let raw = credentialIdentity.recordIdentifier,
              let recordId = Int64(raw) else {
            failSafely(reason: "missing or non-numeric recordIdentifier")
            return
        }
        let id = CredentialId(recordId)
        Task {
            guard let services = await locatorAsync() else {
                failSafely(reason: "ServiceLocator init failed")
                return
            }
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

    // MARK: - PassKey assertion (Phase 5.2, iOS 17+)

    /// Discoverable assertion: iOS focused a passkey form and we pre-fetch a
    /// candidate. The UI path runs through `prepareCredentialList(for:
    /// requestParameters:)` below; this no-UI variant returns
    /// `.userInteractionRequired` so we always get a biometric prompt
    /// (Req 4.1: no silent reveal).
    @available(iOS 17, *)
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            )
        )
    }

    @available(iOS 17, *)
    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier],
        requestParameters: ASPasskeyCredentialRequestParameters
    ) {
        let rpId = requestParameters.relyingPartyIdentifier
        let clientDataHash = requestParameters.clientDataHash
        let allowed = requestParameters.allowedCredentials
        let userVerification = requestParameters.userVerificationPreference

        Task {
            guard let services = await locatorAsync() else {
                failSafely(reason: "ServiceLocator init failed")
                return
            }
            let coordinator = PasskeyAssertionCoordinator(services: services)
            let candidate = await coordinator.pickCandidate(
                rpId: rpId,
                allowedCredentialIDs: allowed
            )
            await MainActor.run {
                renderPasskeyConfirm(
                    candidate: candidate,
                    rpId: rpId,
                    clientDataHash: clientDataHash,
                    userVerification: userVerification,
                    services: services
                )
            }
        }
    }

    @MainActor
    @available(iOS 17, *)
    private func renderPasskeyConfirm(
        candidate: Passkey?,
        rpId: String,
        clientDataHash: Data,
        userVerification: ASAuthorizationPublicKeyCredentialUserVerificationPreference,
        services: ServiceLocator
    ) {
        guard let candidate else {
            failSafely()
            return
        }
        let view = PasskeyConfirmView(
            mode: .assert(rpId: rpId, userName: candidate.userName),
            onConfirm: { [weak self] in
                Task { @MainActor in
                    await self?.runPasskeyAssertion(
                        candidate: candidate,
                        rpId: rpId,
                        clientDataHash: clientDataHash,
                        services: services
                    )
                }
            },
            onCancel: { [weak self] in self?.cancelByUser() }
        )
        hostConfirmView(view)
    }

    @MainActor
    @available(iOS 17, *)
    private func runPasskeyAssertion(
        candidate: Passkey,
        rpId: String,
        clientDataHash: Data,
        services: ServiceLocator
    ) async {
        let auth = await services.biometricAuthenticator
            .authenticate(reason: "Sign in to \(rpId)")
        guard case .succeeded = auth else {
            cancelByUser()
            return
        }

        // Synthesize an ASPasskeyCredentialRequest so the coordinator can
        // reuse the same RP-spoof + sign path as `prepareInterface(forPasskeyAssertion:)`.
        let identity = ASPasskeyCredentialIdentity(
            relyingPartyIdentifier: rpId,
            userName: candidate.userName ?? "",
            credentialID: Base64URL.decode(candidate.credentialId) ?? Data(),
            userHandle: candidate.userHandle,
            recordIdentifier: nil
        )
        let synthRequest = ASPasskeyCredentialRequest(
            credentialIdentity: identity,
            clientDataHash: clientDataHash,
            userVerificationPreference: .preferred,
            supportedAlgorithms: [.ES256]
        )

        let coordinator = PasskeyAssertionCoordinator(services: services)
        switch await coordinator.signAssertion(passkey: candidate, request: synthRequest) {
        case .success(let response):
            extensionContext.completeAssertionRequest(using: response, completionHandler: nil)
        case .notFound, .rpMismatch, .failed:
            failSafely()
        }
    }

    // MARK: - PassKey registration (Phase 5.1, iOS 17+)

    @available(iOS 17, *)
    override func prepareInterface(forPasskeyRegistration registrationRequest: ASCredentialRequest) {
        guard let passkeyRequest = registrationRequest as? ASPasskeyCredentialRequest else {
            failSafely(reason: "registrationRequest is not ASPasskeyCredentialRequest (\(type(of: registrationRequest)))")
            return
        }
        let identity = passkeyRequest.credentialIdentity as? ASPasskeyCredentialIdentity
        let rpId = identity?.relyingPartyIdentifier ?? "unknown site"
        let userName = identity?.userName ?? ""

        // Show the confirm sheet right away so the user sees KeyNest's UI
        // even before the SQLite + Secure Enclave warm-up has finished.
        // ServiceLocator is built in the background; if it fails we close.
        Task {
            guard let services = await locatorAsync() else {
                failSafely(reason: "ServiceLocator init failed")
                return
            }
            let confirm = PasskeyConfirmView(
                mode: .register(rpId: rpId, userName: userName),
                onConfirm: { [weak self] in
                    Task { @MainActor in
                        await self?.runPasskeyRegistration(request: passkeyRequest, services: services)
                    }
                },
                onCancel: { [weak self] in self?.cancelByUser() }
            )
            hostConfirmView(confirm)
        }
    }

    @MainActor
    @available(iOS 17, *)
    private func runPasskeyRegistration(
        request: ASPasskeyCredentialRequest,
        services: ServiceLocator
    ) async {
        let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity
        let rpId = identity?.relyingPartyIdentifier ?? ""
        let auth = await services.biometricAuthenticator
            .authenticate(reason: "Create a passkey for \(rpId)")
        guard case .succeeded = auth else {
            cancelByUser(reason: "biometric auth not succeeded: \(auth)")
            return
        }
        let coordinator = PasskeyRegistrationCoordinator(services: services)
        switch await coordinator.register(request: request) {
        case .success(let credential):
            extensionContext.completeRegistrationRequest(using: credential, completionHandler: nil)
        case .cancelled:
            cancelByUser(reason: "coordinator returned .cancelled")
        case .failed(let reason):
            failSafely(reason: "passkey registration failed: \(reason)")
        }
    }

    // MARK: - Text insertion (iOS 18+)

    @available(iOS 18, *)
    override func prepareInterfaceForUserChoosingTextToInsert() {
        Task {
            guard let services = await locatorAsync() else {
                failSafely(reason: "ServiceLocator init failed")
                return
            }
            do {
                let snapshot = try await services.credentialRepository.listAll(sort: .updatedDesc)
                await MainActor.run {
                    let view = TextInsertPickerView(
                        credentials: snapshot,
                        services: services,
                        onInsert: { [weak self] text in
                            self?.completeTextInsert(text)
                        },
                        onCancel: { [weak self] in self?.cancelByUser() }
                    )
                    hostConfirmView(view)
                }
            } catch {
                failSafely()
            }
        }
    }

    @MainActor
    @available(iOS 18, *)
    private func completeTextInsert(_ text: String) {
        extensionContext.completeRequest(withTextToInsert: text, completionHandler: nil)
    }

    // MARK: - UI hosting helper

    @MainActor
    private func hostConfirmView<V: SwiftUI.View>(_ view: V) {
        // Replace any prior hosted picker / confirm sheet so we never stack.
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let host = UIHostingController(rootView: view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        self.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: - Safe failure / cancel (NFR 3.1)

    private func failSafely(reason: String = "(unspecified)", file: StaticString = #file, line: UInt = #line) {
        // Surface the cause in Console.app and in the NSError so the host browser
        // (Safari) can include it in the WebAuthn error message. webauthn.io
        // still shows the generic "user denied permission" string but the NSLog
        // line lets us pinpoint the failure path.
        NSLog("KNAF failSafely: %@ (%@:%lu)", reason, String(describing: file), line)
        Task { @MainActor in
            extensionContext.cancelRequest(
                withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "KeyNest: \(reason)"]
                )
            )
        }
    }

    private func cancelByUser(reason: String = "(unspecified)", file: StaticString = #file, line: UInt = #line) {
        NSLog("KNAF cancelByUser: %@ (%@:%lu)", reason, String(describing: file), line)
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
