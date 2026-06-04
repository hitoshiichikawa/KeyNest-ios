import XCTest
import CryptoKit
import GRDB
@testable import KeyNest
@testable import KeyNestKit

/// Tests for `PasskeyListViewModel`: observe pipeline + delete passthrough.
/// Backed by a real `PasskeyRepositoryImpl` over an in-memory GRDB queue —
/// the ViewModel is a thin wrapper, so re-stubbing the protocol would just
/// re-test mocks.
@MainActor
final class PasskeyListViewModelTests: XCTestCase {

    func test_observe_emitsEmptyInitially_thenReflectsSavedPasskey() async throws {
        let (services, repo) = try makeServices()
        let viewModel = PasskeyListViewModel(services: services)

        // Kick observation off in the background so the ViewModel starts
        // listening before we insert.
        let observation = Task { await viewModel.observe() }
        // Yield once so the stream subscriber attaches.
        await Task.yield()

        try await repo.save(makeSavePasskeyRequest(credentialId: "abc", rpId: "github.com", userName: "octocat"))

        // GRDB ValueObservation is asynchronous; poll briefly.
        try await waitUntil(timeout: 2.0) { viewModel.passkeys.count == 1 }
        XCTAssertEqual(viewModel.passkeys.first?.rpId, "github.com")
        XCTAssertEqual(viewModel.passkeys.first?.userName, "octocat")

        observation.cancel()
    }

    func test_delete_removesPasskeyFromObservedList() async throws {
        let (services, repo) = try makeServices()
        try await repo.save(makeSavePasskeyRequest(credentialId: "to-delete", rpId: "x.com", userName: "u"))

        let viewModel = PasskeyListViewModel(services: services)
        let observation = Task { await viewModel.observe() }
        await Task.yield()

        try await waitUntil(timeout: 2.0) { viewModel.passkeys.count == 1 }

        await viewModel.delete(viewModel.passkeys[0])

        try await waitUntil(timeout: 2.0) { viewModel.passkeys.isEmpty }

        observation.cancel()
    }

    // MARK: - Helpers

    private func makeServices() throws -> (ServiceLocator, PasskeyRepository) {
        let database = try AppDatabase(DatabaseQueue())
        let keyProvider = ConstantDataKeyProvider()
        let locator = ServiceLocator(database: database, dataKeyProvider: keyProvider)
        return (locator, locator.passkeyRepository)
    }

    private func makeSavePasskeyRequest(credentialId: String, rpId: String, userName: String) -> SavePasskeyRequest {
        SavePasskeyRequest(
            credentialId: credentialId,
            rpId: rpId,
            rpDisplayName: nil,
            userHandle: Data([0x01, 0x02, 0x03]),
            userName: userName,
            userDisplayName: nil,
            isDiscoverable: true,
            privateKey: Data(P256.Signing.PrivateKey().rawRepresentation),
            signCount: 0,
            displayName: nil,
            createdAt: 1
        )
    }

    /// Polls `condition` every 20ms until it returns true or `timeout` elapses.
    /// GRDB `ValueObservation` debounces on a private queue; we can't await it
    /// directly from a `@MainActor` test.
    private func waitUntil(timeout: TimeInterval, condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

/// Constant-key DataKeyProviding for in-memory tests — encryption still happens
/// but no Keychain/Secure Enclave interaction.
private final class ConstantDataKeyProvider: DataKeyProviding {
    private let key = SymmetricKey(size: .bits256)
    func dataKey() throws -> SymmetricKey { key }
    func clearAll() throws {}
}
