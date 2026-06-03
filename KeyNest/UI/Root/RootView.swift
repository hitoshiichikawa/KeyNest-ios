import SwiftUI
import KeyNestKit

/// Top-level shell. Phase 3.2 swaps in `CredentialListView`; Settings /
/// Edit / Danger / Onboarding remain placeholders until 3.3–3.6 land.
struct RootView: View {
    let services: ServiceLocator

    var body: some View {
        NavigationStack {
            CredentialListView(services: services)
        }
        .tint(KNColor.primary)
    }
}

/// Visible breadcrumb so we can confirm the navigation graph + theme are
/// wired before the real screens land.
private struct PhaseStubView: View {
    let phaseTitle: String
    let phaseTask: String

    var body: some View {
        VStack(spacing: 12) {
            Text(phaseTitle)
                .font(KNFont.title2)
                .foregroundStyle(KNColor.text)
            Text("Coming in Phase \(phaseTask)")
                .font(KNFont.callout)
                .foregroundStyle(KNColor.text2)
            StrengthBar(strength: .strong)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
    }
}
