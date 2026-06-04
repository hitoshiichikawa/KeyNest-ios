import SwiftUI
import KeyNestKit

/// Lists stored passkeys for the user to review or delete. Passwords are on
/// the main `CredentialListView`; passkeys live on this dedicated screen
/// because they have a different shape (rp + userName, no editable label /
/// custom fields). Reached from Settings ▸ Passkeys.
struct PasskeyListView: View {
    @State private var viewModel: PasskeyListViewModel

    init(services: ServiceLocator) {
        _viewModel = State(initialValue: PasskeyListViewModel(services: services))
    }

    var body: some View {
        Group {
            if viewModel.passkeys.isEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle("Passkeys")
        .navigationBarTitleDisplayMode(.inline)
        .background(KNColor.bg)
        .task { await viewModel.observe() }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 48))
                .foregroundStyle(KNColor.text3)
            Text("No passkeys yet")
                .font(KNFont.headline)
                .foregroundStyle(KNColor.text)
            Text("Passkeys you create through the iOS AutoFill flow will appear here.")
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
    }

    private var list: some View {
        List {
            ForEach(viewModel.passkeys, id: \.credentialId) { pk in
                PasskeyRow(passkey: pk)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(pk) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(KNColor.bg)
    }
}

private struct PasskeyRow: View {
    let passkey: Passkey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(passkey.displayName ?? passkey.userName ?? "(no name)")
                .font(KNFont.headline)
                .foregroundStyle(KNColor.text)
                .lineLimit(1)
            Text(passkey.rpId)
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text("Created \(formattedDate(passkey.createdAt))")
                if let last = passkey.lastUsedAt {
                    Text("· Last used \(formattedDate(last))")
                }
            }
            .font(KNFont.caption)
            .foregroundStyle(KNColor.text3)
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ epochMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(epochMillis) / 1000.0)
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
