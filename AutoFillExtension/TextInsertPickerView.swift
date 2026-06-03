import SwiftUI
import KeyNestKit

/// Two-step picker shown when the user invokes
/// "Insert Text from KeyNest" from the iOS 18+ keyboard menu.
///
/// Step 1: pick a credential (search + list, same shape as the password
///         AutoFill picker).
/// Step 2: pick a field to insert (username / password / custom rows).
///
/// The biometric prompt + `UnlockVaultUseCase` run between the two steps,
/// inside `TextInsertFieldPickerView`. The owning view controller hands a
/// closure here that completes the extension request.
@available(iOS 18, *)
struct TextInsertPickerView: View {
    let credentials: [Credential]
    let services: ServiceLocator
    let onInsert: (String) -> Void
    let onCancel: () -> Void

    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            List {
                if credentials.isEmpty {
                    Section {
                        Text("Your vault is empty. Add a credential in KeyNest, then try again.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(filtered) { credential in
                            NavigationLink {
                                TextInsertFieldPickerView(
                                    credential: credential,
                                    services: services,
                                    onInsert: onInsert,
                                    onCancel: onCancel
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(credential.label).font(.headline)
                                    Text(credential.username).font(.subheadline).foregroundStyle(.secondary)
                                    Text(credential.serviceIdentifier).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    } header: {
                        Text("Choose a credential")
                    }
                }
            }
            .navigationTitle("Insert from KeyNest")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var filtered: [Credential] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return credentials }
        return credentials.filter {
            $0.label.lowercased().contains(needle)
                || $0.username.lowercased().contains(needle)
                || $0.serviceIdentifier.lowercased().contains(needle)
        }
    }
}

/// Step 2: biometric → decrypt → render `TextToInsertOptions` rows.
@available(iOS 18, *)
struct TextInsertFieldPickerView: View {
    let credential: Credential
    let services: ServiceLocator
    let onInsert: (String) -> Void
    let onCancel: () -> Void

    @State private var phase: Phase = .authenticating
    @State private var options: [InsertableTextField] = []
    @State private var plaintext: PlaintextCredential?

    enum Phase: Equatable {
        case authenticating
        case decrypting
        case ready
        case failed(reason: String)
    }

    var body: some View {
        Group {
            switch phase {
            case .authenticating:
                progress("Authenticating…")
            case .decrypting:
                progress("Unlocking credential…")
            case .ready:
                fieldList
            case .failed(let reason):
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield").font(.system(size: 48)).foregroundStyle(.tertiary)
                    Text("Unable to unlock").font(.headline)
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(credential.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { plaintext?.close() }
    }

    private func progress(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fieldList: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        onInsert(option.value)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName).font(.headline)
                                if option.isSensitive {
                                    Text("Tap to insert").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(option.value).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .privacySensitive(option.isSensitive)
                }
            } header: {
                Text("Choose a field to insert")
            } footer: {
                if options.isEmpty {
                    Text("This credential has no values to insert.")
                }
            }
        }
    }

    private func load() async {
        let auth = await services.biometricAuthenticator
            .authenticate(reason: "Unlock \(credential.label)")
        guard case .succeeded = auth else {
            phase = .failed(reason: "Authentication cancelled")
            return
        }
        phase = .decrypting
        do {
            let unlocked = try await services.unlockVault(credential.id)
            plaintext?.close()
            plaintext = unlocked
            options = TextToInsertOptions.options(from: unlocked)
            phase = .ready
        } catch {
            phase = .failed(reason: String(describing: type(of: error)))
        }
    }
}
