import SwiftUI
import KeyNestKit

/// Danger Zone screen. Req 7.4: requires device-owner authentication AND an
/// explicit confirmation before clearing the vault.
struct DangerZoneView: View {
    @State private var viewModel: DangerZoneViewModel
    @State private var showConfirm: Bool = false

    init(services: ServiceLocator) {
        _viewModel = State(initialValue: DangerZoneViewModel(services: services))
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Clear vault", systemImage: "exclamationmark.octagon.fill")
                        .font(KNFont.headline)
                        .foregroundStyle(KNColor.danger)
                    Text("Permanently removes every credential, passkey, and the data-encryption key. This cannot be undone.")
                        .font(KNFont.callout)
                        .foregroundStyle(KNColor.text2)
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    Task { await viewModel.startClearFlow() }
                } label: {
                    statusLabel
                }
                .disabled(isBusy)
            } footer: {
                phaseFooter
            }
        }
        .scrollContentBackground(.hidden)
        .background(KNColor.bg)
        .navigationTitle("Danger Zone")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.phase) { _, phase in
            showConfirm = (phase == .confirming)
        }
        .confirmationDialog(
            "Clear the entire vault?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await viewModel.confirmAndClear() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelConfirmation()
            }
        } message: {
            Text("All credentials, passkeys, and keys will be erased.")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch viewModel.phase {
        case .authenticating:
            Label("Authenticating…", systemImage: "faceid")
        case .clearing:
            Label("Clearing…", systemImage: "hourglass")
        case .cleared:
            Label("Vault cleared", systemImage: "checkmark.seal")
                .foregroundStyle(KNColor.success)
        default:
            Label("Clear vault", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var phaseFooter: some View {
        switch viewModel.phase {
        case .cleared:
            Text("Add a new credential to start over.")
                .foregroundStyle(KNColor.success)
        case .failed(let reason):
            Text("Operation failed: \(reason)")
                .foregroundStyle(KNColor.danger)
        default:
            EmptyView()
        }
    }

    private var isBusy: Bool {
        switch viewModel.phase {
        case .authenticating, .confirming, .clearing: return true
        default: return false
        }
    }
}
