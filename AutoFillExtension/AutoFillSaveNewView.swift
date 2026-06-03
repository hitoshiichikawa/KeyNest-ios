import SwiftUI
import KeyNestKit

/// "Save a new credential and use it to fill this form" sheet shown inside
/// the AutoFill extension when the user picks `+ Save new for example.com`
/// from `AutoFillPickerView`.
///
/// On `Save`:
/// 1. Validate via `SaveCredentialUseCase` (rejects blank fields).
/// 2. Persist via the use case (encrypts + inserts).
/// 3. Push to `ASCredentialIdentityStore` so the new entry is selectable
///    next time without a vault scan.
/// 4. Return the just-entered username / password to the caller as an
///    `ASPasswordCredential` — iOS feeds them straight into the focused
///    fields, matching the 1Password / Bitwarden flow.
struct AutoFillSaveNewView: View {
    let prefilledServiceIdentifier: String
    let services: ServiceLocator
    let onSave: (String, String) -> Void   // (username, password) → caller builds ASPasswordCredential
    let onCancel: () -> Void

    @State private var label: String
    @State private var serviceIdentifier: String
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var passwordVisible: Bool = false
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(
        prefilledServiceIdentifier: String,
        services: ServiceLocator,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prefilledServiceIdentifier = prefilledServiceIdentifier
        self.services = services
        self.onSave = onSave
        self.onCancel = onCancel
        _serviceIdentifier = State(initialValue: prefilledServiceIdentifier)
        _label = State(initialValue: AutoFillCandidateSelection
            .suggestedLabel(forServiceIdentifier: prefilledServiceIdentifier))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label)
                    TextField("Service identifier", text: $serviceIdentifier, prompt: Text("example.com"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Group {
                            if passwordVisible {
                                TextField("Password", text: $password)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        Button { passwordVisible.toggle() } label: {
                            Image(systemName: passwordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    .privacySensitive()
                } header: {
                    Text("New credential")
                }

                if let err = error {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save in KeyNest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }

        let trimmedSid = serviceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let id = try await services.saveCredential(
                NewCredentialInput(
                    serviceIdentifier: trimmedSid,
                    username: trimmedUser,
                    password: Array(password.utf8),
                    label: trimmedLabel,
                    customFields: []
                )
            )
            await services.identityStoreSync.upsert(
                id: id,
                serviceIdentifier: trimmedSid,
                username: trimmedUser
            )
            onSave(trimmedUser, password)
        } catch SaveCredentialError.serviceIdentifierBlank {
            error = "Service identifier is required."
        } catch SaveCredentialError.usernameBlank {
            error = "Username is required."
        } catch SaveCredentialError.passwordBlank {
            error = "Password is required."
        } catch SaveCredentialError.labelBlank {
            error = "Label is required."
        } catch {
            self.error = "Save failed (\(String(describing: type(of: error))))"
        }
    }
}
