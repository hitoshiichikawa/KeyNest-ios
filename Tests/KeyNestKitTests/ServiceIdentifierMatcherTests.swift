import XCTest
@testable import KeyNestKit

final class ServiceIdentifierMatcherTests: XCTestCase {

    // MARK: - normalize

    func test_normalize_dropsScheme() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("https://example.com"), "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("http://example.com"),  "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("myapp://example.com"), "example.com")
    }

    func test_normalize_dropsPathQueryFragment() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("https://example.com/login"), "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("example.com/path/to?x=1"),   "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("example.com?utm=foo"),       "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("example.com#frag"),          "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("example.com/"),              "example.com")
    }

    func test_normalize_dropsPort() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("example.com:8080"),        "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("https://example.com:443"), "example.com")
    }

    func test_normalize_dropsUserInfo() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("user@example.com"),                 "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("https://user:pwd@example.com/path"), "example.com")
    }

    func test_normalize_dropsTrailingDots() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("example.com."),  "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("example.com..."), "example.com")
    }

    func test_normalize_dropsLeadingWww() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("www.example.com"),         "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("https://www.example.com/"), "example.com")
    }

    func test_normalize_preservesNonWwwSubdomains() {
        // Sub-domain stays distinct: `m.example.com` is NOT `example.com`.
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("m.example.com"),   "m.example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("sub.example.com"), "sub.example.com")
    }

    func test_normalize_lowercasesAndTrims() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("  EXAMPLE.COM  "), "example.com")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("WWW.Example.Com"), "example.com")
    }

    func test_normalize_emptyAndWhitespace() {
        XCTAssertEqual(ServiceIdentifierMatcher.normalize(""),     "")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("   "),  "")
        XCTAssertEqual(ServiceIdentifierMatcher.normalize("\n\t"), "")
    }

    func test_normalize_isIdempotent() {
        let inputs = [
            "https://WWW.Example.com/login?x=1",
            "example.com",
            "m.example.com",
            "user@example.com:443/path",
        ]
        for raw in inputs {
            let once = ServiceIdentifierMatcher.normalize(raw)
            let twice = ServiceIdentifierMatcher.normalize(once)
            XCTAssertEqual(once, twice, "normalize should be idempotent for \(raw)")
        }
    }

    // MARK: - matches

    func test_matches_canonicalizesBothSides() {
        XCTAssertTrue(ServiceIdentifierMatcher.matches(
            stored: "https://www.example.com/",
            requested: "EXAMPLE.com"
        ))
    }

    func test_matches_rejectsSubdomainMismatch() {
        XCTAssertFalse(ServiceIdentifierMatcher.matches(
            stored: "example.com",
            requested: "m.example.com"
        ))
        XCTAssertFalse(ServiceIdentifierMatcher.matches(
            stored: "sub.example.com",
            requested: "example.com"
        ))
    }

    func test_matches_emptyNeverMatches() {
        XCTAssertFalse(ServiceIdentifierMatcher.matches(stored: "",          requested: ""))
        XCTAssertFalse(ServiceIdentifierMatcher.matches(stored: "",          requested: "example.com"))
        XCTAssertFalse(ServiceIdentifierMatcher.matches(stored: "example.com", requested: ""))
        // Whitespace-only normalizes to empty and should not match anything.
        XCTAssertFalse(ServiceIdentifierMatcher.matches(stored: "   ",       requested: "example.com"))
    }

    func test_matches_differentSites() {
        XCTAssertFalse(ServiceIdentifierMatcher.matches(
            stored: "example.com",
            requested: "example.org"
        ))
        XCTAssertFalse(ServiceIdentifierMatcher.matches(
            stored: "example.com",
            requested: "examp1e.com"  // typosquat
        ))
    }
}
