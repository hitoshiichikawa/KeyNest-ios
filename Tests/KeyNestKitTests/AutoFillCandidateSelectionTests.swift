import XCTest
@testable import KeyNestKit

final class AutoFillCandidateSelectionTests: XCTestCase {

    private func makeCredential(id: Int64, sid: String, user: String = "u") -> Credential {
        Credential(
            id: CredentialId(id),
            serviceIdentifier: sid,
            username: user,
            label: "L",
            createdAt: 1,
            updatedAt: 1,
            lastUsedAt: nil
        )
    }

    // MARK: filter

    func test_filter_emptyRequested_returnsAll() {
        let all = [makeCredential(id: 1, sid: "a.com"), makeCredential(id: 2, sid: "b.com")]
        XCTAssertEqual(
            AutoFillCandidateSelection
                .filter(all: all, requestedRawServiceIdentifiers: [])
                .map(\.id.value),
            [1, 2]
        )
    }

    func test_filter_normalizesBothSides() {
        let all = [
            makeCredential(id: 1, sid: "https://www.example.com/"),
            makeCredential(id: 2, sid: "other.org"),
        ]
        let hits = AutoFillCandidateSelection.filter(
            all: all,
            requestedRawServiceIdentifiers: ["EXAMPLE.com"]
        )
        XCTAssertEqual(hits.map(\.id.value), [1])
    }

    func test_filter_emptyStoredNeverMatches() {
        let all = [makeCredential(id: 1, sid: "")]
        let hits = AutoFillCandidateSelection.filter(
            all: all,
            requestedRawServiceIdentifiers: [""]
        )
        XCTAssertTrue(hits.isEmpty, "empty stored identifier must not match anything")
    }

    func test_filter_subdomainsAreDistinct() {
        let all = [
            makeCredential(id: 1, sid: "example.com"),
            makeCredential(id: 2, sid: "m.example.com"),
        ]
        let hits = AutoFillCandidateSelection.filter(
            all: all,
            requestedRawServiceIdentifiers: ["m.example.com"]
        )
        XCTAssertEqual(hits.map(\.id.value), [2])
    }

    func test_filter_dedupesNeedlesAcrossInputs() {
        let all = [makeCredential(id: 1, sid: "example.com")]
        let hits = AutoFillCandidateSelection.filter(
            all: all,
            requestedRawServiceIdentifiers: ["example.com", "EXAMPLE.com", "https://example.com/"]
        )
        XCTAssertEqual(hits.map(\.id.value), [1])
    }

    // MARK: suggestedServiceIdentifier

    func test_suggestedServiceIdentifier_picksFirstUsable() {
        XCTAssertEqual(
            AutoFillCandidateSelection.suggestedServiceIdentifier(from: ["", "  ", "https://example.com/"]),
            "example.com"
        )
    }

    func test_suggestedServiceIdentifier_emptyWhenNoneUsable() {
        XCTAssertEqual(
            AutoFillCandidateSelection.suggestedServiceIdentifier(from: ["", "  "]),
            ""
        )
        XCTAssertEqual(AutoFillCandidateSelection.suggestedServiceIdentifier(from: []), "")
    }

    // MARK: suggestedLabel

    func test_suggestedLabel_usesNormalizedIdentifier() {
        XCTAssertEqual(
            AutoFillCandidateSelection.suggestedLabel(forServiceIdentifier: "https://www.GitHub.com/"),
            "github.com"
        )
    }

    func test_suggestedLabel_emptyFallsBackToGeneric() {
        XCTAssertEqual(
            AutoFillCandidateSelection.suggestedLabel(forServiceIdentifier: ""),
            "New credential"
        )
        XCTAssertEqual(
            AutoFillCandidateSelection.suggestedLabel(forServiceIdentifier: "   "),
            "New credential"
        )
    }
}
