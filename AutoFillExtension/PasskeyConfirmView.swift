import SwiftUI

/// Tiny SwiftUI confirm sheet shown before running the passkey ceremony.
/// Lives in the extension target only (host app has no equivalent surface).
struct PasskeyConfirmView: View {
    enum Mode {
        case register(rpId: String, userName: String)
        case assert(rpId: String, userName: String?)

        var title: String {
            switch self {
            case .register: return "Create a passkey?"
            case .assert:   return "Sign in with passkey?"
            }
        }

        var rpId: String {
            switch self {
            case .register(let rp, _): return rp
            case .assert(let rp, _):   return rp
            }
        }

        var subtitle: String {
            switch self {
            case .register(_, let user): return "Account: \(user)"
            case .assert(_, let user):   return user.map { "Account: \($0)" } ?? ""
            }
        }
    }

    let mode: Mode
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 48))
                Text(mode.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(mode.rpId)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if !mode.subtitle.isEmpty {
                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Button(action: onConfirm) {
                    Text(primaryLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .cancel, action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(24)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var primaryLabel: String {
        switch mode {
        case .register: return "Create passkey"
        case .assert:   return "Continue"
        }
    }
}
