import Foundation

/// Pure helpers shared by the AutoFill extension's picker and "save new"
/// flow. Lives in `KeyNestKit` (not the extension target) so the logic is
/// unit-testable without importing AuthenticationServices.
public enum AutoFillCandidateSelection {

    /// Filters a vault snapshot down to credentials that match any of the
    /// requested service identifiers (already-normalized OR raw — the
    /// helper re-normalizes everything through `ServiceIdentifierMatcher`).
    ///
    /// Empty `requested` returns the full list as-is (caller may want to
    /// show "All credentials" when the OS didn't constrain us). An empty
    /// stored `serviceIdentifier` never matches anything (guards against
    /// the empty-string degenerate case).
    public static func filter(
        all: [Credential],
        requestedRawServiceIdentifiers requested: [String]
    ) -> [Credential] {
        guard !requested.isEmpty else { return all }
        let needles = Set(requested.map(ServiceIdentifierMatcher.normalize))
        return all.filter { credential in
            let stored = ServiceIdentifierMatcher.normalize(credential.serviceIdentifier)
            return !stored.isEmpty && needles.contains(stored)
        }
    }

    /// Picks the best service identifier to prefill on the "save new"
    /// form. Returns the **first non-empty normalized** identifier, or an
    /// empty string when none of the inputs are usable.
    public static func suggestedServiceIdentifier(
        from rawIdentifiers: [String]
    ) -> String {
        for raw in rawIdentifiers {
            let normalized = ServiceIdentifierMatcher.normalize(raw)
            if !normalized.isEmpty { return normalized }
        }
        return ""
    }

    /// Suggested human-readable label for a new credential when the user
    /// invokes "save new" from the AutoFill picker. Uses the normalized
    /// service identifier verbatim (`github.com` → `github.com`); falls back
    /// to a generic placeholder when no identifier is known.
    public static func suggestedLabel(forServiceIdentifier sid: String) -> String {
        let normalized = ServiceIdentifierMatcher.normalize(sid)
        return normalized.isEmpty ? "New credential" : normalized
    }
}
