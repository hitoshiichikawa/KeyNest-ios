import Foundation
import Observation
import KeyNestKit

/// Backs the credential edit screen. iOS port of Android
/// `CredentialEditViewModel`, scoped to the password use cases (passkey edit /
/// detected-fields suggestions are Non-Goals per design).
///
/// Lifecycle highlights:
/// - **New mode**: validate inputs and dispatch `SaveCredentialUseCase`.
/// - **Edit mode**: gate the screen behind `LAContext` device-owner auth (Req
///   4.1) → call `UnlockVaultUseCase` to populate fields → dispatch
///   `UpdateCredentialUseCase` on save.
/// - Custom-field rows are clamped to 10 (Req 7.2).
/// - Duplicate detection runs in the background as the service identifier /
///   username settle; it surfaces a non-blocking warning (the user can save
///   anyway — parity with Android's soft warning).
@MainActor
@Observable
final class CredentialEditViewModel {
    enum Mode: Equatable {
        case new
        case edit(CredentialId)
    }

    enum Field: Equatable { case serviceIdentifier, username, password, label }
    enum ErrorKind: Equatable { case blank, invalid }

    enum LoadPhase: Equatable {
        /// New mode never enters a loading state.
        case ready
        case authenticating
        case decrypting
        case authCancelled
        case authFailed(message: String)
        case loadFailed(reason: String)
    }

    let mode: Mode

    var serviceIdentifier: String = "" { didSet { scheduleDuplicateCheck() } }
    var username: String = ""           { didSet { scheduleDuplicateCheck() } }
    var password: String = ""
    var label: String = ""
    var customFields: [EditableCustomField] = []
    var passwordVisible: Bool = false

    var fieldError: (field: Field, kind: ErrorKind)?
    var saveError: String?
    var loadPhase: LoadPhase = .ready
    var isSaving: Bool = false
    var duplicateWarning: String?
    var actionMessage: ActionMessage?

    /// Set to a non-nil id when the screen should pop back to the list (saved /
    /// deleted / duplicated). The view observes and dismisses.
    var dismissTo: DismissTarget?

    @ObservationIgnored private let services: ServiceLocator
    @ObservationIgnored private var duplicateCheckTask: Task<Void, Never>?
    @ObservationIgnored private var loadedPlaintext: PlaintextCredential?

    static let maxCustomFields = 10

    init(mode: Mode, services: ServiceLocator) {
        self.mode = mode
        self.services = services
    }

    deinit {
        duplicateCheckTask?.cancel()
        // loadedPlaintext is released here; its own deinit calls close().
    }

    var isEdit: Bool {
        if case .edit = mode { return true } else { return false }
    }

    var canAddCustomField: Bool { customFields.count < Self.maxCustomFields }

    // MARK: - Load (edit mode)

    /// Runs the biometric prompt and decrypts the stored credential. View
    /// invokes this from `.task` exactly once when the screen mounts. New
    /// mode short-circuits to `.ready` so the form is editable immediately.
    func loadIfNeeded() async {
        guard case .edit(let id) = mode else { return }
        guard loadPhase == .ready || isLoadRetryable else { return }

        loadPhase = .authenticating
        let auth = await services.biometricAuthenticator
            .authenticate(reason: "Unlock credential to edit")
        switch auth {
        case .succeeded:
            break
        case .cancelled:
            loadPhase = .authCancelled
            return
        case .failed(_, let message):
            loadPhase = .authFailed(message: message)
            return
        case .unavailable:
            loadPhase = .authFailed(message: "Device authentication is not available.")
            return
        }

        loadPhase = .decrypting
        do {
            let plaintext = try await services.unlockVault(id)
            loadedPlaintext?.close()
            loadedPlaintext = plaintext
            populate(from: plaintext)
            loadPhase = .ready
        } catch {
            loadPhase = .loadFailed(reason: String(describing: type(of: error)))
        }
    }

    private var isLoadRetryable: Bool {
        switch loadPhase {
        case .authCancelled, .authFailed, .loadFailed: return true
        default: return false
        }
    }

    private func populate(from plaintext: PlaintextCredential) {
        serviceIdentifier = plaintext.serviceIdentifier
        username = plaintext.username
        label = plaintext.label
        password = String(decoding: plaintext.password, as: UTF8.self)
        customFields = plaintext.customFields.map {
            EditableCustomField(key: $0.fieldKey, value: $0.value)
        }
    }

    // MARK: - Mutations

    func addCustomFieldRow() {
        guard canAddCustomField else { return }
        customFields.append(EditableCustomField(key: "", value: ""))
    }

    func removeCustomFieldRow(at index: Int) {
        guard customFields.indices.contains(index) else { return }
        customFields.remove(at: index)
    }

    // MARK: - Clipboard

    func copyPassword() {
        guard !password.isEmpty else { return }
        CredentialClipboard.copySecret(password, to: services.pasteboard)
        actionMessage = ActionMessage(kind: .success, text: "Password copied")
    }

    func copyUsername() {
        let trimmed = trim(username)
        guard !trimmed.isEmpty else { return }
        CredentialClipboard.copyPlain(trimmed, to: services.pasteboard)
        actionMessage = ActionMessage(kind: .success, text: "Username copied")
    }

    func copyCustomFieldValue(at index: Int) {
        guard customFields.indices.contains(index) else { return }
        let value = customFields[index].value
        guard !value.isEmpty else { return }
        CredentialClipboard.copySecret(value, to: services.pasteboard)
        actionMessage = ActionMessage(kind: .success, text: "Value copied")
    }

    // MARK: - Save

    func save() async {
        fieldError = nil
        saveError = nil

        if let blank = firstBlankField() {
            fieldError = (field: blank, kind: .blank)
            return
        }
        let cleanFields = sanitizedCustomFields()
        guard cleanFields.count <= Self.maxCustomFields else {
            saveError = "Custom fields exceed the limit of \(Self.maxCustomFields)."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let sid = trim(serviceIdentifier)
            let user = trim(username)
            switch mode {
            case .new:
                let id = try await services.saveCredential(
                    NewCredentialInput(
                        serviceIdentifier: sid,
                        username: user,
                        password: Array(password.utf8),
                        label: trim(label),
                        customFields: cleanFields
                    )
                )
                await services.identityStoreSync.upsert(
                    id: id, serviceIdentifier: sid, username: user
                )
                dismissTo = .saved(id)
            case .edit(let id):
                let original = loadedPlaintext
                let originalPassword = original.map { String(decoding: $0.password, as: UTF8.self) }
                let newPassword: [UInt8]? = (originalPassword == password) ? nil : Array(password.utf8)
                let originalServiceIdentifier = original?.serviceIdentifier
                let originalUsername = original?.username
                try await services.updateCredential(
                    UpdateCredentialInput(
                        id: id,
                        serviceIdentifier: sid,
                        username: user,
                        label: trim(label),
                        newPassword: newPassword,
                        customFields: cleanFields
                    )
                )
                // If the identifying tuple changed, drop the stale entry then
                // upsert the new one so the OS can't surface both.
                if let prevSid = originalServiceIdentifier,
                   let prevUser = originalUsername,
                   (prevSid != sid || prevUser != user) {
                    await services.identityStoreSync.remove(
                        id: id, serviceIdentifier: prevSid, username: prevUser
                    )
                }
                await services.identityStoreSync.upsert(
                    id: id, serviceIdentifier: sid, username: user
                )
                dismissTo = .saved(id)
            }
        } catch let error as SaveCredentialError {
            applyValidation(error)
        } catch let error as UpdateCredentialError {
            applyValidation(error)
        } catch {
            saveError = "Save failed (\(String(describing: type(of: error))))"
        }
    }

    func delete() async {
        guard case .edit(let id) = mode else { return }
        let auth = await services.biometricAuthenticator
            .authenticate(reason: "Confirm deletion")
        guard case .succeeded = auth else { return }
        let sid = trim(serviceIdentifier)
        let user = trim(username)
        do {
            try await services.deleteCredential(id)
            await services.identityStoreSync.remove(
                id: id, serviceIdentifier: sid, username: user
            )
            dismissTo = .deleted(id)
        } catch {
            saveError = "Delete failed (\(String(describing: type(of: error))))"
        }
    }

    func duplicate() async {
        guard case .edit(let id) = mode else { return }
        let sid = trim(serviceIdentifier)
        let user = trim(username)
        do {
            let newId = try await services.duplicateCredential(id)
            await services.identityStoreSync.upsert(
                id: newId, serviceIdentifier: sid, username: user
            )
            dismissTo = .duplicated(newId)
        } catch {
            saveError = "Duplicate failed (\(String(describing: type(of: error))))"
        }
    }

    // MARK: - Duplicate detection (background)

    /// Debounced lookup: if another credential already binds this
    /// service-identifier + username, surface a soft warning. The user can
    /// save anyway — matches Android's non-blocking warning.
    private func scheduleDuplicateCheck() {
        duplicateCheckTask?.cancel()
        let sid = trim(serviceIdentifier)
        let user = trim(username)
        guard !sid.isEmpty, !user.isEmpty else { duplicateWarning = nil; return }
        let currentId: CredentialId? = {
            if case .edit(let id) = mode { return id } else { return nil }
        }()
        duplicateCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let matches = try await self.services.credentialRepository
                    .findByServiceIdentifier(sid)
                let other = matches.first { c in
                    c.username.caseInsensitiveCompare(user) == .orderedSame
                        && c.id != currentId
                }
                self.duplicateWarning = other.map { "Already saved as \"\($0.label)\"" }
            } catch {
                self.duplicateWarning = nil
            }
        }
    }

    // MARK: - Helpers

    private func firstBlankField() -> Field? {
        if trim(label).isEmpty            { return .label }
        if trim(serviceIdentifier).isEmpty { return .serviceIdentifier }
        if trim(username).isEmpty          { return .username }
        if password.isEmpty                { return .password }
        return nil
    }

    private func sanitizedCustomFields() -> [CustomField] {
        customFields
            .filter { !trim($0.key).isEmpty || !$0.value.isEmpty }
            .map { CustomField(fieldKey: trim($0.key), value: $0.value) }
    }

    private func applyValidation(_ error: SaveCredentialError) {
        switch error {
        case .labelBlank:              fieldError = (.label, .blank)
        case .serviceIdentifierBlank:  fieldError = (.serviceIdentifier, .blank)
        case .usernameBlank:           fieldError = (.username, .blank)
        case .passwordBlank:           fieldError = (.password, .blank)
        }
    }

    private func applyValidation(_ error: UpdateCredentialError) {
        switch error {
        case .labelBlank:              fieldError = (.label, .blank)
        case .serviceIdentifierBlank:  fieldError = (.serviceIdentifier, .blank)
        case .usernameBlank:           fieldError = (.username, .blank)
        case .notFound:                saveError = "Credential no longer exists."
        }
    }

    private func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct EditableCustomField: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}

enum DismissTarget: Equatable {
    case saved(CredentialId)
    case deleted(CredentialId)
    case duplicated(CredentialId)
}
