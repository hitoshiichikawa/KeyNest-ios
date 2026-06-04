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
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false

    var body: some Scene {
        WindowGroup {
            AppShell(
                services: services,
                startupError: startupError,
                onboardingComplete: $onboardingComplete,
                bootstrap: bootstrap
            )
        }
    }

    private func bootstrap() async {
        do {
            let locator = try ServiceLocator.makeShared()

            if CommandLine.arguments.contains("--reset-onboarding") {
                onboardingComplete = false
            }

            if DemoSeeder.isRequested() {
                try await DemoSeeder.seed(services: locator)
                onboardingComplete = true
            }

            services = locator
            // Reconcile the OS credential-identity store with the vault so
            // the AutoFill UI never goes stale after an app launch (entries
            // added by the autofill extension, manual edits between launches,
            // etc.). best-effort: swallow errors.
            Task.detached {
                do {
                    let snapshot = try await locator.credentialRepository.listAll(sort: .updatedDesc)
                    await locator.identityStoreSync.replaceAll(with: snapshot)
                } catch {
                    // SafeLog at the framework level already logs sync errors;
                    // a snapshot fetch failure here is non-fatal.
                }
            }
        } catch {
            startupError = error
        }
    }
}

/// Holds the running app content + a privacy shield. The shield is drawn
/// whenever the scene is not active (App Switcher, control center, incoming
/// call), so the system snapshot taken when the app suspends never captures
/// vault contents (NFR 1.2).
private struct AppShell: View {
    let services: ServiceLocator?
    let startupError: Error?
    @Binding var onboardingComplete: Bool
    let bootstrap: () async -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            content

            if scenePhase != .active {
                PrivacyShield()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: scenePhase == .active)
    }

    @ViewBuilder
    private var content: some View {
        if let services {
            if onboardingComplete {
                RootView(services: services)
            } else {
                OnboardingView(onContinue: { onboardingComplete = true })
            }
        } else if let err = startupError {
            StartupErrorView(error: err)
        } else {
            Color(KNColor.bg)
                .ignoresSafeArea()
                .task { await bootstrap() }
        }
    }
}

/// Full-screen overlay that hides vault contents during App Switcher
/// transitions and similar phase changes. Simple brand chrome only — no
/// secrets, no live data.
private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            KNColor.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(KNColor.primary)
                Text("KeyNest")
                    .font(KNFont.title3)
                    .foregroundStyle(KNColor.text2)
            }
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
