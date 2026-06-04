import SwiftUI
import AuthenticationServices

/// First-run onboarding. Req 7.5: guide the user to enable KeyNest as an
/// AutoFill provider; surface `PasskeyProviderStatus`. On iOS 17+ the
/// "Open Settings" button deep-links into Settings ▸ Passwords ▸ AutoFill
/// Passwords & Passkeys via `ASSettingsHelper`; on earlier OSes it falls back
/// to the app's own Settings page (the only public option pre-17).
///
/// Completion is up to the user: tapping "Continue" persists a flag via
/// `@AppStorage("onboardingComplete")` from the parent, which then swaps
/// in the main `RootView`. When the user actually enables AutoFill while
/// the screen is visible, the CTA flips to "Continue" with a success label.
struct OnboardingView: View {
    let onContinue: () -> Void

    @State private var viewModel = OnboardingViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    autofillStatusCard
                    StepList()
                    passkeyStatusCard
                }
                .padding(24)
            }

            footer
        }
        .background(KNColor.bg.ignoresSafeArea())
        .task { await viewModel.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refresh() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 36))
                .foregroundStyle(KNColor.primary)
            Text("Welcome to KeyNest")
                .font(KNFont.title)
                .foregroundStyle(KNColor.text)
            Text("Offline-first password & passkey vault, encrypted on this device.")
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
        }
    }

    private var autofillStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.autofillEnabled ? "checkmark.seal.fill" : "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(viewModel.autofillEnabled ? KNColor.success : KNColor.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.autofillEnabled ? "AutoFill is enabled" : "AutoFill is not enabled")
                    .font(KNFont.headline)
                    .foregroundStyle(KNColor.text)
                Text(viewModel.autofillEnabled
                     ? "KeyNest will fill credentials in Safari and apps."
                     : "Open Settings to add KeyNest as a provider.")
                    .font(KNFont.callout)
                    .foregroundStyle(KNColor.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(KNColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(KNColor.border, lineWidth: 1)
        )
    }

    private var passkeyStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 24))
                .foregroundStyle(passkeyTint)
            VStack(alignment: .leading, spacing: 2) {
                Text("PassKey provider")
                    .font(KNFont.headline)
                    .foregroundStyle(KNColor.text)
                Text(passkeyText)
                    .font(KNFont.callout)
                    .foregroundStyle(passkeyTint)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(KNColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if !viewModel.autofillEnabled {
                Button {
                    ASSettingsHelper.openCredentialProviderAppSettings { _ in }
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(KNColor.primary)
                .controlSize(.large)
            }

            Button(action: onContinue) {
                Text(viewModel.autofillEnabled ? "Continue" : "Skip for now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(24)
        .background(KNColor.bgElev)
    }

    private var passkeyText: String {
        switch viewModel.passkeyStatus {
        case .enabled:     return "Available — passkeys can be created and used."
        case .disabled:    return "Will activate once AutoFill is enabled."
        case .unsupported: return "Requires iOS 17 or newer."
        }
    }

    private var passkeyTint: Color {
        switch viewModel.passkeyStatus {
        case .enabled:     return KNColor.success
        case .disabled:    return KNColor.warning
        case .unsupported: return KNColor.text3
        }
    }
}

/// Three numbered steps that mirror the iOS AutoFill enablement path
/// (iOS does not allow deep-linking directly to the toggle).
private struct StepList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Step(number: 1, text: "Open Settings ▸ General ▸ AutoFill & Passwords.")
            Step(number: 2, text: "Tap AutoFill Passwords & Passkeys.")
            Step(number: 3, text: "Enable KeyNest, then return here.")
        }
    }

    private struct Step: View {
        let number: Int
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(KNFont.headline)
                    .frame(width: 24, height: 24)
                    .background(KNColor.primaryContainer)
                    .foregroundStyle(KNColor.onPrimaryContainer)
                    .clipShape(Circle())
                Text(text)
                    .font(KNFont.body)
                    .foregroundStyle(KNColor.text2)
                Spacer(minLength: 0)
            }
        }
    }
}
