import SwiftUI
import KeyNestKit

/// Settings screen. Req 7.3 (Phase 3.4).
///
/// Surfaces:
/// - AutoFill status (with a "Open Settings" deep link)
/// - Lock method (DeviceLockStatus)
/// - Vault metadata (count, last updated, storage)
/// - PassKey provider status
/// - OSS licenses entry (3.5)
/// - Danger Zone entry (3.5)
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let services: ServiceLocator

    init(services: ServiceLocator) {
        self.services = services
        _viewModel = State(initialValue: SettingsViewModel(services: services))
    }

    var body: some View {
        Form {
            Section {
                LabelValueRow(
                    title: "AutoFill provider",
                    value: viewModel.autofillEnabled ? "Enabled" : "Disabled",
                    valueColor: viewModel.autofillEnabled ? KNColor.success : KNColor.warning
                )
                LabelValueRow(
                    title: "PassKey provider",
                    value: passkeyText,
                    valueColor: passkeyColor
                )
                if !viewModel.autofillEnabled {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Enable in Settings", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("AutoFill")
            } footer: {
                Text("Open Settings ▸ Passwords ▸ AutoFill Passwords & Passkeys, then enable KeyNest.")
                    .font(KNFont.caption)
            }

            Section {
                LabelValueRow(title: "Lock method", value: lockText)
            } header: {
                Text("Security")
            }

            Section {
                LabelValueRow(title: "Credentials", value: "\(viewModel.vault.count)")
                LabelValueRow(
                    title: "Last updated",
                    value: formattedDate(viewModel.vault.latestUpdatedAt)
                )
                LabelValueRow(
                    title: "Storage",
                    value: formattedBytes(viewModel.storageBytes)
                )
            } header: {
                Text("Vault")
            }

            Section {
                NavigationLink {
                    PlaceholderView(title: "Open-Source Licenses", task: "3.5")
                } label: {
                    Label("Open-source licenses", systemImage: "doc.text")
                }
            } header: {
                Text("About")
            }

            Section {
                NavigationLink {
                    PlaceholderView(title: "Danger Zone", task: "3.5")
                } label: {
                    Label("Danger zone", systemImage: "exclamationmark.octagon")
                        .foregroundStyle(KNColor.danger)
                }
            } footer: {
                Text("Clearing the vault permanently removes every credential, passkey, and key.")
                    .font(KNFont.caption)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KNColor.bg)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.observeVault() }
        .task { await viewModel.refreshSnapshots() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refreshSnapshots() }
            }
        }
    }

    // MARK: - Derived display

    private var passkeyText: String {
        switch viewModel.passkeyStatus {
        case .enabled:     return "Enabled"
        case .disabled:    return "Disabled"
        case .unsupported: return "Requires iOS 17"
        }
    }

    private var passkeyColor: Color {
        switch viewModel.passkeyStatus {
        case .enabled:     return KNColor.success
        case .disabled:    return KNColor.warning
        case .unsupported: return KNColor.text3
        }
    }

    private var lockText: String {
        switch viewModel.lockStatus {
        case .biometricAndDeviceCredential: return "Biometrics + passcode"
        case .deviceCredentialOnly:         return "Passcode only"
        case .noLock:                       return "No lock set"
        }
    }

    private func formattedDate(_ epochMillis: Int64?) -> String {
        guard let ms = epochMillis else { return "Never" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct LabelValueRow: View {
    let title: String
    let value: String
    var valueColor: Color = KNColor.text2

    var body: some View {
        HStack {
            Text(title)
                .font(KNFont.body)
                .foregroundStyle(KNColor.text)
            Spacer()
            Text(value)
                .font(KNFont.callout)
                .foregroundStyle(valueColor)
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let task: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(KNFont.title3)
                .foregroundStyle(KNColor.text)
            Text("Coming in Phase \(task)")
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
