import SwiftUI

/// Shown the instant the AutoFill extension viewController loads, before
/// `ServiceLocator.makeShared()` (which opens the SQLite vault and unwraps the
/// Secure-Enclave KEK — ~hundreds of ms cold) returns. Without this the user
/// sees a blank canvas during cold start; with it, perceived latency drops to
/// "KeyNest is already loading" + a brand mark.
struct LoadingPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            ProgressView()
                .progressViewStyle(.circular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
