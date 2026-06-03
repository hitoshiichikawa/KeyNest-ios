import XCTest
@testable import KeyNestKit

/// Unit tests for `VaultStorageMeasurer` (Phase 2.2). Points the measurer at a
/// temp file so the byte count is deterministic and independent of the App Group.
final class VaultStorageMeasurerTests: XCTestCase {

    func test_measureBytes_returnsFileSize() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keynest-measure-\(UUID().uuidString).db")
        let payload = Data(repeating: 0xAB, count: 1234)
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let measurer = VaultStorageMeasurer(databaseURL: { url })
        let bytes = await measurer.measureBytes()

        // No -wal / -shm sidecars exist, so the total is just the DB file size.
        XCTAssertEqual(bytes, 1234)
    }

    func test_measureBytes_missingFile_returnsZero() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keynest-missing-\(UUID().uuidString).db")
        let measurer = VaultStorageMeasurer(databaseURL: { url })

        let bytes = await measurer.measureBytes()

        XCTAssertEqual(bytes, 0)
    }

    func test_measureBytes_noDatabaseURL_returnsZero() async throws {
        let measurer = VaultStorageMeasurer(databaseURL: { nil })
        let bytes = await measurer.measureBytes()
        XCTAssertEqual(bytes, 0)
    }
}
