import SwiftUI
import KeyNestKit

/// Credential edit / create screen. Req 7.2 (Phase 3.3).
///
/// New mode renders an editable empty form. Edit mode gates the screen
/// behind a biometric prompt; on cancel the user sees a retry CTA, on
/// success the form is populated from the decrypted `PlaintextCredential`.
/// Domain Picker (Phase 4) is deferred until `ServiceIdentifierMatcher`
/// lands — for now the service identifier is a free-form TextField.
struct CredentialEditView: View {
    @State private var viewModel: CredentialEditViewModel
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(mode: CredentialEditViewModel.Mode, services: ServiceLocator) {
        _viewModel = State(initialValue: CredentialEditViewModel(mode: mode, services: services))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.isEdit ? "Edit credential" : "New credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task { await viewModel.loadIfNeeded() }
            .confirmationDialog(
                "Delete credential?",
                isPresented: $showDeleteConfirm
            ) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the credential and its custom fields.")
            }
            .onChange(of: viewModel.dismissTo) { _, target in
                if target != nil { dismiss() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadPhase {
        case .authenticating, .decrypting:
            LoadingView(phase: viewModel.loadPhase)
        case .authCancelled, .authFailed, .loadFailed:
            LoadRetryView(phase: viewModel.loadPhase) {
                Task { await viewModel.loadIfNeeded() }
            }
        case .ready:
            form
        }
    }

    private var form: some View {
        Form {
            Section("Identity") {
                LabeledField(
                    title: "Label",
                    text: $viewModel.label,
                    error: viewModel.fieldError?.field == .label ? "Required" : nil
                )
                LabeledField(
                    title: "Service identifier",
                    text: $viewModel.serviceIdentifier,
                    error: viewModel.fieldError?.field == .serviceIdentifier ? "Required" : nil,
                    keyboard: .URL,
                    autocapitalization: .never,
                    prompt: "example.com",
                    help: "Web domain (e.g. example.com). For apps, use the app's official website domain."
                )
                LabeledField(
                    title: "Username",
                    text: $viewModel.username,
                    error: viewModel.fieldError?.field == .username ? "Required" : nil,
                    autocapitalization: .never
                )
                PasswordField(
                    text: $viewModel.password,
                    visible: $viewModel.passwordVisible,
                    error: viewModel.fieldError?.field == .password ? "Required" : nil
                )
            }
            if let warning = viewModel.duplicateWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(KNFont.callout)
                        .foregroundStyle(KNColor.warning)
                }
            }
            Section {
                ForEach(Array(viewModel.customFields.enumerated()), id: \.element.id) { index, _ in
                    CustomFieldRow(field: $viewModel.customFields[index]) {
                        viewModel.removeCustomFieldRow(at: index)
                    }
                }
                Button {
                    viewModel.addCustomFieldRow()
                } label: {
                    Label("Add custom field", systemImage: "plus.circle")
                }
                .disabled(!viewModel.canAddCustomField)
            } header: {
                HStack {
                    Text("Custom fields")
                    Spacer()
                    Text("\(viewModel.customFields.count)/\(CredentialEditViewModel.maxCustomFields)")
                        .foregroundStyle(KNColor.text3)
                }
            }
            if viewModel.isEdit {
                Section {
                    Button {
                        Task { await viewModel.duplicate() }
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if let err = viewModel.saveError {
                Section {
                    Text(err)
                        .font(KNFont.caption)
                        .foregroundStyle(KNColor.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KNColor.bg)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task { await viewModel.save() }
            }
            .disabled(viewModel.isSaving)
        }
    }
}

// MARK: - Subviews

private struct LabeledField: View {
    let title: String
    @Binding var text: String
    var error: String?
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var prompt: LocalizedStringKey? = nil
    var help: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                title,
                text: $text,
                prompt: prompt.map { Text($0) }
            )
                .font(KNFont.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(keyboard != .default)
            if let error {
                Text(error)
                    .font(KNFont.caption)
                    .foregroundStyle(KNColor.danger)
            } else if let help {
                Text(help)
                    .font(KNFont.caption)
                    .foregroundStyle(KNColor.text3)
            }
        }
    }
}

private struct PasswordField: View {
    @Binding var text: String
    @Binding var visible: Bool
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Group {
                    if visible {
                        TextField("Password", text: $text)
                            .font(KNFont.mono(15))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Password", text: $text)
                            .font(KNFont.mono(15))
                    }
                }
                Button {
                    visible.toggle()
                } label: {
                    Image(systemName: visible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(visible ? "Hide password" : "Show password")
            }
            if let error {
                Text(error)
                    .font(KNFont.caption)
                    .foregroundStyle(KNColor.danger)
            }
        }
        .privacySensitive()
    }
}

private struct CustomFieldRow: View {
    @Binding var field: EditableCustomField
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 4) {
                TextField("Key", text: $field.key)
                    .font(KNFont.callout)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Value", text: $field.value)
                    .font(KNFont.body)
                    .autocorrectionDisabled()
            }
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(KNColor.danger)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove custom field")
        }
        .privacySensitive()
    }
}

private struct LoadingView: View {
    let phase: CredentialEditViewModel.LoadPhase

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
    }

    private var message: String {
        switch phase {
        case .authenticating: return "Authenticating…"
        case .decrypting:     return "Unlocking credential…"
        default:              return ""
        }
    }
}

private struct LoadRetryView: View {
    let phase: CredentialEditViewModel.LoadPhase
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(KNColor.text3)
            Text(title)
                .font(KNFont.title3)
                .foregroundStyle(KNColor.text)
            if let detail {
                Text(detail)
                    .font(KNFont.callout)
                    .foregroundStyle(KNColor.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(KNColor.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
    }

    private var title: String {
        switch phase {
        case .authCancelled: return "Authentication cancelled"
        case .authFailed:    return "Authentication failed"
        case .loadFailed:    return "Unable to unlock"
        default:             return ""
        }
    }

    private var detail: String? {
        switch phase {
        case .authFailed(let message): return message
        case .loadFailed(let reason):  return reason
        default:                       return nil
        }
    }
}
