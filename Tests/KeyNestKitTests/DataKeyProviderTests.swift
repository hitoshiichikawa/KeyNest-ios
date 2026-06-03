import XCTest
import CryptoKit
@testable import KeyNestKit

/// Unit tests for `DataKeyProvider` (Phase 1 task 1.2 / Req 3.2, 3.3, 7.4).
///
/// These exercise the key-lifecycle logic against an in-memory `DataKeyStore`
/// fake. The real `Security`-framework backend (`KeychainDataKeyStore`,
/// Secure-Enclave ECIES + shared Keychain) needs an entitled host app and is
/// verified on Mac/device, mirroring KeyNest Android's instrumented
/// `KeystoreKeyProviderTest`.
final class DataKeyProviderTests: XCTestCase {

    private func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private func fixedBytes(_ byte: UInt8) -> (Int) throws -> Data {
        { count in Data(repeating: byte, count: count) }
    }

    // MARK: Fallback (no Secure Enclave) — Req 3.3

    func test_fallback_firstCallGeneratesAndPersists32ByteKey() throws {
        let store = FakeDataKeyStore(seals: false)
        let provider = DataKeyProvider(store: store, randomBytes: fixedBytes(0x07))

        let key = try provider.dataKey()

        XCTAssertEqual(keyData(key).count, 32)
        // Fallback persists the raw DEK verbatim (no sealing).
        XCTAssertEqual(store.persisted, Data(repeating: 0x07, count: 32))
        XCTAssertEqual(store.sealCount, 0)
    }

    func test_secondCallReturnsCachedKey_withoutRegenerating() throws {
        var generations = 0
        let store = FakeDataKeyStore(seals: false)
        let provider = DataKeyProvider(store: store, randomBytes: { count in
            generations += 1
            return Data(repeating: UInt8(generations), count: count)
        })

        let first = try provider.dataKey()
        let second = try provider.dataKey()

        XCTAssertEqual(keyData(first), keyData(second))
        XCTAssertEqual(generations, 1, "the DEK must be generated only once")
    }

    func test_existingKeyIsLoaded_notRegenerated() throws {
        let store = FakeDataKeyStore(seals: false)
        let existing = Data(repeating: 0x5A, count: 32)
        try store.addSealedDataKey(existing)

        let provider = DataKeyProvider(store: store, randomBytes: fixedBytes(0x01))
        let key = try provider.dataKey()

        XCTAssertEqual(keyData(key), existing)
        XCTAssertEqual(store.addCount, 1, "no new key should be added when one exists")
    }

    // MARK: Secure-Enclave envelope — Req 3.2

    func test_sealing_persistsSealedBlob_andAFreshProcessOpensIt() throws {
        let store = FakeDataKeyStore(seals: true)
        let provider = DataKeyProvider(store: store, randomBytes: fixedBytes(0x42))

        let created = try provider.dataKey()

        // Persisted material is sealed (marker-prefixed), never the raw DEK.
        XCTAssertEqual(store.sealCount, 1)
        XCTAssertNotEqual(store.persisted, Data(repeating: 0x42, count: 32))
        XCTAssertEqual(store.persisted?.first, FakeDataKeyStore.sealMarker)

        // Simulate the extension process: a fresh provider over the same store
        // must open the sealed blob back to the identical DEK.
        let reopened = try DataKeyProvider(store: store, randomBytes: fixedBytes(0x99)).dataKey()
        XCTAssertEqual(store.openCount, 1)
        XCTAssertEqual(keyData(created), keyData(reopened))
    }

    // MARK: First-launch race — adopt the winner, never clobber

    func test_duplicateOnAdd_adoptsThePersistedWinner() throws {
        let winning = Data(repeating: 0xC3, count: 32)
        let store = RaceLosingStore(winningKey: winning)
        let provider = DataKeyProvider(store: store, randomBytes: fixedBytes(0x11))

        let key = try provider.dataKey()

        // We lost the race: must return the persisted key, not our fresh one.
        XCTAssertEqual(keyData(key), winning)
    }

    // MARK: clearAll — Req 7.4

    func test_clearAll_dropsKeyMaterial_andNextCallMintsAFreshKey() throws {
        var generations = 0
        let store = FakeDataKeyStore(seals: false)
        let provider = DataKeyProvider(store: store, randomBytes: { count in
            generations += 1
            return Data(repeating: UInt8(generations), count: count)
        })

        let original = try provider.dataKey()
        try provider.clearAll()

        XCTAssertNil(store.persisted, "sealed DEK must be deleted")
        XCTAssertEqual(store.deleteSealingKeyCount, 1, "the sealing key must be deleted too")

        let regenerated = try provider.dataKey()
        XCTAssertNotEqual(keyData(original), keyData(regenerated), "a fresh key after clear")
    }

    // MARK: Corrupt material

    func test_storedKeyOfWrongLength_throwsInvalidKeyData() throws {
        let store = FakeDataKeyStore(seals: false)
        try store.addSealedDataKey(Data(repeating: 0x00, count: 10))  // not 32 bytes
        let provider = DataKeyProvider(store: store, randomBytes: fixedBytes(0x07))

        XCTAssertThrowsError(try provider.dataKey()) { error in
            XCTAssertEqual(error as? DataKeyError, .invalidKeyData)
        }
    }
}

// MARK: - Test doubles

/// In-memory `DataKeyStore`. `seals == true` exercises the Secure-Enclave path
/// with a marker-prefix stand-in for ECIES sealing.
private final class FakeDataKeyStore: DataKeyStore {
    static let sealMarker: UInt8 = 0xEE

    let sealsKeyMaterial: Bool
    private(set) var persisted: Data?
    private(set) var sealCount = 0
    private(set) var openCount = 0
    private(set) var addCount = 0
    private(set) var deleteSealingKeyCount = 0

    init(seals: Bool) { self.sealsKeyMaterial = seals }

    func loadSealedDataKey() throws -> Data? { persisted }

    func addSealedDataKey(_ blob: Data) throws {
        addCount += 1
        if persisted != nil { throw DataKeyError.duplicateItem }
        persisted = blob
    }

    func deleteSealedDataKey() throws { persisted = nil }

    func seal(_ rawKey: Data) throws -> Data {
        sealCount += 1
        return Data([Self.sealMarker]) + rawKey
    }

    func open(_ sealed: Data) throws -> Data {
        openCount += 1
        guard sealed.first == Self.sealMarker else { throw DataKeyError.openFailed }
        return sealed.dropFirst()
    }

    func deleteSealingKey() throws { deleteSealingKeyCount += 1 }
}

/// Simulates losing the first-launch race: the load before our add returns nil,
/// the add raises `duplicateItem`, and the subsequent load returns the winner.
private final class RaceLosingStore: DataKeyStore {
    let sealsKeyMaterial = false
    private let winningKey: Data
    private var winnerVisible = false

    init(winningKey: Data) { self.winningKey = winningKey }

    func loadSealedDataKey() throws -> Data? { winnerVisible ? winningKey : nil }

    func addSealedDataKey(_ blob: Data) throws {
        winnerVisible = true   // the other process committed between our load and add
        throw DataKeyError.duplicateItem
    }

    func deleteSealedDataKey() throws {}
    func seal(_ rawKey: Data) throws -> Data { rawKey }
    func open(_ sealed: Data) throws -> Data { sealed }
    func deleteSealingKey() throws {}
}
