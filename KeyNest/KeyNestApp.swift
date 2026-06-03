import SwiftUI
import KeyNestKit

/// App entry point. Constructs the production `ServiceLocator` once and
/// passes it down through `RootView`. iOS equivalent of Android's
/// `KeyNestApp` (`Application.onCreate` → `ServiceLocator.initialize`).
///
/// `ServiceLocator.makeShared()` opens the App Group SQLite database and
/// resolves the Secure-Enclave-wrapped DEK; we fail fast on construction
/// errors rather than render a degraded UI without the vault.
@main
struct KeyNestApp: App {
    @State private var services: ServiceLocator?
    @State private var startupError: Error?

    var body: some Scene {
        WindowGroup {
            if let services {
                RootView(services: services)
            } else if let startupError {
                StartupErrorView(error: startupError)
            } else {
                Color(KNColor.bg)
                    .ignoresSafeArea()
                    .task { await bootstrap() }
            }
        }
    }

    private func bootstrap() async {
        do {
            services = try ServiceLocator.makeShared()
        } catch {
            startupError = error
        }
    }
}

/// Bare-bones failure surface. Phase 3.4 settings will replace this with a
/// proper diagnostics path.
private struct StartupErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(KNColor.danger)
            Text("Unable to open vault")
                .font(KNFont.title3)
                .foregroundStyle(KNColor.text)
            Text(String(describing: type(of: error)))
                .font(KNFont.caption)
                .foregroundStyle(KNColor.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KNColor.bg)
    }
}
