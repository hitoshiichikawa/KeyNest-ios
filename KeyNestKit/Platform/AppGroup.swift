import Foundation

/// Shared-container identifiers used by both the app and the AutoFill extension.
///
/// Keep these in sync with `project.yml` and the two `*.entitlements` files.
/// The Keychain group is prefixed by the Team ID at runtime via
/// `$(AppIdentifierPrefix)` in the entitlement.
public enum AppGroup {
    /// App Group container that holds the SQLite vault so the app and the
    /// extension see the same database file.
    public static let identifier = "group.io.github.hitoshiichikawa.ios.keynest"

    /// Shared Keychain access group that holds the Secure-Enclave-wrapped data
    /// key. iOS 17+ with a wildcard provisioning profile rejects the bare-suffix
    /// form (`-34018 errSecMissingEntitlement`), so we assemble the team-prefixed
    /// full form (`<TEAM_ID>.<suffix>`) from `KNTeamIdentifier` injected into
    /// the host bundle's Info.plist via `$(DEVELOPMENT_TEAM)`. When the team
    /// id is missing (Simulator without a signed entitlement, fresh checkout
    /// without Local.xcconfig), returns nil so the caller omits the access
    /// group attribute and falls back to the default app-local keychain.
    public static var keychainAccessGroup: String? {
        #if targetEnvironment(simulator)
        // Simulator has no signed entitlements, so any access group attribute
        // would 34018 the Keychain call. Fall back to the default app-local
        // keychain (extension parity is lost on Sim — by design).
        return nil
        #else
        let bareSuffix = "io.github.hitoshiichikawa.ios.keynest.shared"
        guard let teamId = Bundle.main.object(forInfoDictionaryKey: "KNTeamIdentifier") as? String,
              !teamId.isEmpty else {
            return nil
        }
        return "\(teamId).\(bareSuffix)"
        #endif
    }

    /// SQLite database file name inside the shared container.
    public static let databaseFileName = "keynest.db"

    /// Absolute URL of the shared database. Prefers the App Group container
    /// (production: app ⇄ extension share the vault). On Simulator builds
    /// where the App Group entitlement is unavailable (no signing identity),
    /// falls back to the host app's Application Support directory so the
    /// SwiftUI shell still boots for visual / smoke testing.
    ///
    /// The fallback is **app-local** — the AutoFill extension cannot see it.
    /// Production behavior on signed devices is unchanged.
    public static func databaseURL(
        fileManager: FileManager = .default
    ) -> URL? {
        if let shared = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return shared.appendingPathComponent(databaseFileName)
        }
        #if targetEnvironment(simulator)
        SafeLog.warn("App Group container unavailable; using local Application Support (Simulator fallback)")
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return support.appendingPathComponent(databaseFileName)
        #else
        return nil
        #endif
    }
}
