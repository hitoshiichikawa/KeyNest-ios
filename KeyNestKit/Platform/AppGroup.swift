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

    /// Shared Keychain access group that holds the Secure-Enclave-wrapped data key.
    /// At runtime the real prefix is the Team ID; Keychain queries use the bare
    /// suffix when the entitlement lists `$(AppIdentifierPrefix)…`.
    public static let keychainAccessGroup = "io.github.hitoshiichikawa.ios.keynest.shared"

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
