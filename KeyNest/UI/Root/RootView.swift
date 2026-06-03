import SwiftUI
import KeyNestKit

/// Top-level shell for the KeyNest app.
///
/// Phase 3.1 lands the navigation skeleton only. The Credential List
/// (3.2), Edit (3.3), Settings (3.4), Danger Zone (3.5) and Onboarding
/// (3.6) screens will be wired in subsequent commits. Each placeholder
/// below reserves the visual slot so the navigation graph compiles end
/// to end.
struct RootView: View {
    let services: ServiceLocator

    var body: some View {
        NavigationStack {
            PhaseStubView(
                phaseTitle: "Credential List",
                phaseTask: "3.2"
            )
            .navigationTitle("KeyNest")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PhaseStubView(phaseTitle: "Settings", phaseTask: "3.4")
                            .navigationTitle("Settings")
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
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
