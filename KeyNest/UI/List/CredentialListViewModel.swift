import Foundation
import Observation
import KeyNestKit

/// Backs the credential list screen.
///
/// iOS port of Android `CredentialListViewModel`. Two simplifications for v1:
/// 1. **No signature-chip filter** — Android partitions by `signatureSha256`
///    presence; iOS has no package-signature concept (design Non-Goals).
/// 2. **Password rows only** — Android merges passkey rows into the list via
///    `CredentialListSorting.mergeAndSort`. The iOS list keeps the passkey
///    surface in Settings / its own screen (Req 7.3); password list parity
///    (search / sort / recently-used / empty states) is the Req 7.1 contract.
///
/// Observation model: the main list re-subscribes to `ListCredentialsUseCase`
/// whenever `sort` changes. SwiftUI consumes this via `.task(id: vm.sort)` on
/// the view side (the iOS equivalent of Kotlin `flatMapLatest`). The
/// recently-used carousel is independent and consumed via a separate `.task`.
@MainActor
@Observable
final class CredentialListViewModel {
    var query: String = ""
    var sort: CredentialSortOrder = .updatedDesc

    /// Last snapshot pushed by the observation stream for the active sort.
    var allCredentials: [Credential] = []
    var recentList: [Credential] = []
    var observationError: String?

    /// One-shot user feedback for duplicate / delete actions. The view binds
    /// this to a transient banner / alert and clears it on dismiss.
    var actionMessage: ActionMessage?

    @ObservationIgnored private let listUseCase: ListCredentialsUseCase
    @ObservationIgnored private let recentUseCase: ObserveRecentlyUsedUseCase
    @ObservationIgnored private let duplicateUseCase: DuplicateCredentialUseCase
    @ObservationIgnored private let deleteUseCase: DeleteCredentialUseCase

    init(services: ServiceLocator) {
        self.listUseCase = services.listCredentials
        self.recentUseCase = services.observeRecentlyUsed
        self.duplicateUseCase = services.duplicateCredential
        self.deleteUseCase = services.deleteCredential
    }

    // MARK: - Derived state

    var filteredList: [Credential] {
        Self.applySearch(allCredentials, query: query)
    }

    var emptyKind: EmptyKind? {
        Self.computeEmptyKind(filtered: filteredList, query: query)
    }

    // MARK: - Observation

    /// Re-subscribes for the given sort order. Awaits until the surrounding
    /// `.task(id:)` is cancelled (sort change → restart, view disappear → end).
    func observeMain(sort: CredentialSortOrder) async {
        observationError = nil
        do {
            for try await rows in listUseCase(order: sort) {
                allCredentials = rows
            }
        } catch is CancellationError {
            return
        } catch {
            observationError = String(describing: type(of: error))
        }
    }

    func observeRecent() async {
        do {
            for try await rows in recentUseCase() {
                recentList = rows
            }
        } catch is CancellationError {
            return
        } catch {
            // Recently-used is a soft surface; swallow but keep the main
            // stream's error path authoritative.
        }
    }

    // MARK: - Actions

    func onQueryChanged(_ value: String) { query = value }
    func onSortChanged(_ value: CredentialSortOrder) { sort = value }

    func duplicate(_ id: CredentialId) async {
        do {
            _ = try await duplicateUseCase(id)
            actionMessage = ActionMessage(kind: .success, text: "Duplicated")
        } catch {
            actionMessage = ActionMessage(
                kind: .failure,
                text: "Duplicate failed (\(String(describing: type(of: error))))"
            )
        }
    }

    func delete(_ id: CredentialId) async {
        do {
            try await deleteUseCase(id)
        } catch {
            actionMessage = ActionMessage(
                kind: .failure,
                text: "Delete failed (\(String(describing: type(of: error))))"
            )
        }
    }

    // MARK: - Pure helpers (testable)

    /// Case-insensitive substring contains across label / username /
    /// serviceIdentifier. Blank query is a no-op. Port of Android
    /// `CredentialListViewModel.applySearch` (signature-chip filter dropped).
    static func applySearch(_ list: [Credential], query: String) -> [Credential] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return list }
        return list.filter { c in
            c.label.lowercased().contains(needle)
                || c.username.lowercased().contains(needle)
                || c.serviceIdentifier.lowercased().contains(needle)
        }
    }

    /// `.initial` when the user has not narrowed at all (query blank AND the
    /// underlying snapshot is empty); `.noMatch` when the query / filters do
    /// produce an empty intersection. Nil when the rendered list is non-empty.
    static func computeEmptyKind(filtered: [Credential], query: String) -> EmptyKind? {
        guard filtered.isEmpty else { return nil }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .initial
            : .noMatch
    }
}

enum EmptyKind: Equatable {
    case initial, noMatch
}

struct ActionMessage: Identifiable, Equatable {
    enum Kind { case success, failure }
    let id = UUID()
    let kind: Kind
    let text: String
}
