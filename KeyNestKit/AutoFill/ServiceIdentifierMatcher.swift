import Foundation

/// Normalizes free-form URLs / domains down to a canonical comparison key, and
/// matches a stored credential's `serviceIdentifier` against an incoming OS
/// request.
///
/// iOS-only concern: Android matched by package name (an opaque, already-
/// canonical identifier). iOS's AutoFill provider receives `URL` or `domain`
/// service identifiers from web pages and apps, so equality has to survive
/// real-world variance (`https://`, trailing `/`, `WWW.`, port, …).
///
/// Normalization (idempotent):
/// 1. Trim whitespace + lowercase.
/// 2. Drop scheme (`http://`, `https://`, `myapp://`).
/// 3. Drop userInfo (`user:pwd@…`).
/// 4. Drop port (`:8080`).
/// 5. Drop path / query / fragment (everything from first `/`, `?`, `#`).
/// 6. Drop trailing `.` (DNS root label form).
/// 7. Drop leading `www.`.
///
/// Match: two identifiers match iff their normalized form is byte-equal AND
/// non-empty. Sub-domain matching is intentionally **strict** — `m.example.com`
/// does NOT match a stored `example.com` and vice versa. False fills on
/// look-alike domains are a higher cost than the inconvenience of saving
/// per-subdomain entries (parity with Apple's own behavior on
/// `ASCredentialServiceIdentifier`).
public enum ServiceIdentifierMatcher {
    /// Canonical normalization. Always returns ASCII-lowercased bytes
    /// (Unicode IDN handling stays out of scope for this phase — the OS
    /// hands us already-decoded `URL`/domain strings).
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let schemeEnd = s.range(of: "://") {
            s.removeSubrange(s.startIndex..<schemeEnd.upperBound)
        }
        if let at = s.firstIndex(of: "@") {
            s.removeSubrange(s.startIndex...at)
        }
        for terminator in ["/", "?", "#"] as [Character] {
            if let idx = s.firstIndex(of: terminator) {
                s.removeSubrange(idx..<s.endIndex)
            }
        }
        if let colon = s.firstIndex(of: ":") {
            s.removeSubrange(colon..<s.endIndex)
        }
        while s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s
    }

    /// True iff `stored` and `requested` normalize to the same non-empty host.
    public static func matches(stored: String, requested: String) -> Bool {
        let normalizedStored = normalize(stored)
        return !normalizedStored.isEmpty
            && normalizedStored == normalize(requested)
    }
}
