import Foundation
import AuthenticationServices

/// Mirrors the KeyNest vault into iOS's system-wide
/// `ASCredentialIdentityStore` so the OS can surface KeyNest entries in the
/// AutoFill UI on matching sites / apps.
///
/// iOS-only concern: Android built fill responses on demand (Activity →
/// `AssistStructure` → `FillResponse`). iOS pre-registers `ASPasswordCredentialIdentity`
/// objects ahead of time and the system consults them itself when a form is
/// focused. We therefore have to push every CRUD event through this sync.
///
/// Strategy:
/// - **Replace** (`replaceCredentials`) on a full snapshot — used at app launch
///   or after vault clear to recover from any drift between vault and store.
/// - **Save** (`saveCredentials`) on per-row insert / update — iOS upserts by
///   `(serviceIdentifier, recordIdentifier)`.
/// - **Remove** (`removeCredentials`) on delete.
///
/// All entries use the normalized service identifier (Phase 4.1
/// `ServiceIdentifierMatcher`) so what the OS compares against matches what
/// the credential edit screen stored.
///
/// Safety: every call short-circuits when the user has not enabled KeyNest as
/// an AutoFill provider (`state.isEnabled == false`) — pushing to a disabled
/// store wastes IPC and the OS clears it on disable anyway.
public protocol CredentialIdentityStoreSyncing: Sendable {
    /// Full-snapshot reconciliation; used at app launch and after vault clear.
    func replaceAll(with credentials: [Credential]) async
    /// Idempotent insert / update keyed by `(serviceIdentifier, recordIdentifier)`.
    func upsert(id: CredentialId, serviceIdentifier: String, username: String) async
    /// Removes the identity that corresponds to the given record.
    func remove(id: CredentialId, serviceIdentifier: String, username: String) async
    /// Drops every identity (Danger Zone).
    func removeAll() async
}

public actor CredentialIdentityStoreSync: CredentialIdentityStoreSyncing {
    private let store: ASCredentialIdentityStore

    public init(store: ASCredentialIdentityStore = .shared) {
        self.store = store
    }

    public func replaceAll(with credentials: [Credential]) async {
        guard await isEnabled() else { return }
        let identities = credentials.map {
            Self.makeIdentity(
                id: $0.id,
                serviceIdentifier: $0.serviceIdentifier,
                username: $0.username
            )
        }
        do {
            try await store.replaceCredentialIdentities(identities)
        } catch {
            SafeLog.warn("identity-store replace failed", error: error)
        }
    }

    public func upsert(id: CredentialId, serviceIdentifier: String, username: String) async {
        guard await isEnabled() else { return }
        let identity = Self.makeIdentity(id: id, serviceIdentifier: serviceIdentifier, username: username)
        do {
            try await store.saveCredentialIdentities([identity])
        } catch {
            SafeLog.warn("identity-store save failed", error: error)
        }
    }

    public func remove(id: CredentialId, serviceIdentifier: String, username: String) async {
        guard await isEnabled() else { return }
        let identity = Self.makeIdentity(id: id, serviceIdentifier: serviceIdentifier, username: username)
        do {
            try await store.removeCredentialIdentities([identity])
        } catch {
            SafeLog.warn("identity-store remove failed", error: error)
        }
    }

    public func removeAll() async {
        guard await isEnabled() else { return }
        do {
            try await store.removeAllCredentialIdentities()
        } catch {
            SafeLog.warn("identity-store removeAll failed", error: error)
        }
    }

    // MARK: - Helpers

    private func isEnabled() async -> Bool {
        await store.state().isEnabled
    }

    private static func makeIdentity(
        id: CredentialId,
        serviceIdentifier: String,
        username: String
    ) -> ASPasswordCredentialIdentity {
        let normalized = ServiceIdentifierMatcher.normalize(serviceIdentifier)
        return ASPasswordCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(
                identifier: normalized,
                type: .domain
            ),
            user: username,
            recordIdentifier: String(id.value)
        )
    }
}

/// No-op variant for hosts that can't link `AuthenticationServices` (tests,
/// preview shims). Keeps `ServiceLocator` happy without forcing every consumer
/// to import AS.
public struct NoopCredentialIdentityStoreSync: CredentialIdentityStoreSyncing {
    public init() {}
    public func replaceAll(with credentials: [Credential]) async {}
    public func upsert(id: CredentialId, serviceIdentifier: String, username: String) async {}
    public func remove(id: CredentialId, serviceIdentifier: String, username: String) async {}
    public func removeAll() async {}
}
