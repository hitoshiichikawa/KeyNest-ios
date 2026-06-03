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

    /// Absolute URL of the shared database, or nil if the App Group is not
    /// provisioned (misconfiguration — callers should treat as fatal).
    public static func databaseURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(databaseFileName)
    }
}
